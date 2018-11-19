{-# LANGUAGE BangPatterns  #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE MagicHash     #-}

module Data.Map.NonEmpty.Internal (
    NEMap(..)
  , toMap
  , foldr
  , foldr'
  , foldr1
  , foldr1'
  , foldl
  , foldl'
  , foldl1
  , foldl1'
  , union
  , elems
  , size
  , traverseWithKey
  , foldMapWithKey
  , insertMinMap
  , insertMaxMap
  , valid
  ) where

import           Control.Applicative
import           Data.Function
import           Data.Functor.Apply
import           Data.List.NonEmpty         (NonEmpty(..))
import           Data.Map                   (Map)
import           Data.Maybe hiding          (mapMaybe)
import           Data.Semigroup
import           Data.Semigroup.Foldable    (Foldable1(fold1))
import           Data.Semigroup.Traversable (Traversable1(..))
import           GHC.Exts                   ( reallyUnsafePtrEquality#, isTrue# )
import           Prelude hiding             (lookup, foldr1, foldl1, foldr, foldl, filter, map)
import qualified Data.Foldable              as F
import qualified Data.Map                   as M
import qualified Data.Map.Internal          as M
import qualified Data.Semigroup.Foldable    as F1


data NEMap k a =
    NEMap { nemK0  :: !k   -- ^ invariant: must be smaller than smallest key in map
          , nemV0  :: a
          , nemMap :: !(Map k a)
          }
  deriving (Eq, Ord, Functor)

foldr :: (a -> b -> b) -> b -> NEMap k a -> b
foldr f z (NEMap _ v m) = v `f` M.foldr f z m

foldr' :: (a -> b -> b) -> b -> NEMap k a -> b
foldr' f z (NEMap _ v m) = v `f` y
  where
    !y = M.foldr' f z m

foldr1 :: (a -> a -> a) -> NEMap k a -> a
foldr1 f (NEMap _ v m) = maybe v (f v . uncurry (M.foldr f))
                       . M.maxView
                       $ m

foldr1' :: (a -> a -> a) -> NEMap k a -> a
foldr1' f (NEMap _ v m) = case M.maxView m of
    Nothing      -> v
    Just (y, m') -> let !z = M.foldr' f y m' in v `f` z

foldl :: (a -> b -> a) -> a -> NEMap k b -> a
foldl f z (NEMap _ v m) = M.foldl f (f z v) m

foldl' :: (a -> b -> a) -> a -> NEMap k b -> a
foldl' f z (NEMap _ v m) = M.foldl' f x m
  where
    !x = f z v

foldl1 :: (a -> a -> a) -> NEMap k a -> a
foldl1 f (NEMap _ v m) = M.foldl f v m

foldl1' :: (a -> a -> a) -> NEMap k a -> a
foldl1' f (NEMap _ v m) = M.foldl' f v m

-- TODO: benchmark against maxView method
foldMapWithKey
    :: Semigroup m
    => (k -> a -> m)
    -> NEMap k a
    -> m
foldMapWithKey f (NEMap k0 v m) = maybe (f k0 v) (f k0 v <>)
                                . getOption
                                . M.foldMapWithKey (\k -> Option . Just . f k)
                                $ m

foldMap1 :: Semigroup m => (a -> m) -> NEMap k a -> m
foldMap1 f = foldMapWithKey (const f)

union
    :: Ord k
    => NEMap k a
    -> NEMap k a
    -> NEMap k a
union n1@(NEMap k1 v1 m1) n2@(NEMap k2 v2 m2) = case compare k1 k2 of
    LT -> NEMap k1 v1 . M.union m1 . toMap $ n2
    EQ -> NEMap k1 v1 . M.union m1 . toMap $ n2
    GT -> NEMap k2 v2 . M.union (toMap n1) $ m2

elems :: NEMap k a -> NonEmpty a
elems (NEMap _ v m) = v :| M.elems m

size :: NEMap k a -> Int
size (NEMap _ _ m) = 1 + M.size m

toMap :: NEMap k a -> Map k a
toMap (NEMap k v m) = insertMinMap k v m

-- TODO: benchmark against maxView-based methods
traverseWithKey
    :: Apply t
    => (k -> a -> t b)
    -> NEMap k a
    -> t (NEMap k b)
traverseWithKey f (NEMap k0 v m0) = case runMaybeApply m1 of
    Left  m2 -> NEMap k0 <$> f k0 v <.> m2
    Right m2 -> flip (NEMap k0) m2 <$> f k0 v
  where
    m1 = M.traverseWithKey (\k -> MaybeApply . Left . f k) m0

-- | Left-biased union
instance Ord k => Semigroup (NEMap k a) where
    (<>) = union

-- | Traverses elements in order ascending keys
--
-- 'foldr1', 'foldl1', 'minimum', 'maximum' are all total.
instance Foldable (NEMap k) where
    fold      (NEMap _ v m) = v <> F.fold m
    foldMap f (NEMap _ v m) = f v <> foldMap f m
    foldr   = foldr
    foldr'  = foldr'
    foldr1  = foldr1
    foldl   = foldl
    foldl'  = foldl'
    foldl1  = foldl1
    null _  = False
    length  = size
    elem x (NEMap _ v m) = F.elem x m
                        || x == v
    minimum (NEMap _ v _) = v
    maximum (NEMap _ v m) = maybe v snd . M.lookupMax $ m
    toList  = F.toList . elems

-- | Traverses elements in order ascending keys
instance Traversable (NEMap k) where
    traverse f (NEMap k v m) = NEMap k <$> f v <*> traverse f m
    sequenceA (NEMap k v m)  = NEMap k <$> v <*> sequenceA m

-- | Traverses elements in order ascending keys
instance Foldable1 (NEMap k) where
    foldMap1   = foldMap1
    fold1 (NEMap _ v m) = maybe v (v <>)
                        . getOption
                        . F.foldMap (Option . Just)
                        $ m
    toNonEmpty = elems

-- | Traverses elements in order ascending keys
instance Traversable1 (NEMap k) where
    traverse1 f = traverseWithKey (const f)
    sequence1 (NEMap k v m0) = case runMaybeApply m1 of
        Left  m2 -> NEMap k <$> v <.> m2
        Right m2 -> flip (NEMap k) m2 <$> v
      where
        m1 = traverse (MaybeApply . Left) m0

-- | /O(n)/. Test if the internal map structure is valid.
valid :: Ord k => NEMap k a -> Bool
valid (NEMap k _ m) = M.valid m
                   && all ((k <) . fst . fst) (M.minViewWithKey m)







-- | /O(log n)/. Insert new key and value into a map where keys are
-- /strictly greater than/ the new key.  That is, the new key must be
-- /strictly less than/ all keys present in the 'Map'.  /The precondition
-- is not checked./
--
-- While this has the same asymptotics as 'M.insert', it saves a constant
-- factor for key comparison (so may be helpful if comparison is
-- expensive) and also does not require an 'Ord' instance for the key type.
insertMinMap :: k -> a -> Map k a -> Map k a
insertMinMap kx0 = go kx0 kx0
  where
    go :: k -> k -> a -> Map k a -> Map k a
    go orig !_  x M.Tip = M.singleton (lazy orig) x
    go orig !kx x t@(M.Bin _ ky y l r)
        | l' `ptrEq` l = t
        | otherwise    = M.balanceL ky y l' r
      where
        !l' = go orig kx x l

-- | /O(log n)/. Insert new key and value into a map where keys are
-- /strictly less than/ the new key.  That is, the new key must be
-- /strictly greater than/ all keys present in the 'Map'.  /The
-- precondition is not checked./
--
-- While this has the same asymptotics as 'M.insert', it saves a constant
-- factor for key comparison (so may be helpful if comparison is
-- expensive) and also does not require an 'Ord' instance for the key type.
insertMaxMap :: k -> a -> Map k a -> Map k a
insertMaxMap kx0 = go kx0 kx0
  where
    go :: k -> k -> a -> Map k a -> Map k a
    go orig !_  x M.Tip = M.singleton (lazy orig) x
    go orig !kx x t@(M.Bin _ ky y l r)
        | r' `ptrEq` r = t
        | otherwise    = M.balanceR ky y l r'
      where
        !r' = go orig kx x r

lazy :: a -> a
lazy x = x

ptrEq :: a -> a -> Bool
ptrEq x y = isTrue# (reallyUnsafePtrEquality# x y)