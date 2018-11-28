{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns    #-}

module Data.Sequence.NonEmpty (
  -- * Finite sequences
    NESeq ((:<||), (:||>))
  -- ** Conversions between empty and non-empty sequences
  -- , pattern IsNonEmpty
  -- , pattern IsEmpty
  , nonEmptySeq
  , toSeq
  , withNonEmpty
  , unsafeFromSeq
  -- * Construction
  , singleton
  , (<|)
  , (|>)
  , (><)
  , fromList
  -- ** Repetition
  , replicate
  , replicateA
  , replicateA1
  , replicateM
  -- , cycleTaking
  -- ** Iterative construction
  , iterateN
  , unfoldr
  , unfoldl
  -- * Deconstruction
  -- | Additional functions for deconstructing sequences are available
  -- via the 'Foldable' instance of 'Seq'.

  -- ** Queries
  , length
  --   -- ** Views
  -- , ViewL(..)
  -- , viewl
  -- , ViewR(..)
  -- , viewr
  -- * Scans
  , scanl
  , scanl1
  , scanr
  , scanr1
  -- * Sublists
  , tails
  , inits
  , chunksOf
  -- ** Sequential searches
  , takeWhileL
  , takeWhileR
  , dropWhileL
  , dropWhileR
  , spanl
  , spanr
  , breakl
  , breakr
  , partition
  , filter
  --   -- * Sorting
  -- , sort
  -- , sortBy
  -- , sortOn
  -- , unstableSort
  -- , unstableSortBy
  -- , unstableSortOn
  --   -- * Indexing
  -- , lookup
  -- , (!?)
  -- , index
  -- , adjust
  -- , adjust'
  -- , update
  -- , take
  -- , drop
  -- , insertAt
  -- , deleteAt
  , splitAt
  -- ** Indexing with predicates
  -- | These functions perform sequential searches from the left
  -- or right ends of the sequence  returning indices of matching
  -- elements.
  -- , elemIndexL
  -- , elemIndicesL
  -- , elemIndexR
  -- , elemIndicesR
  -- , findIndexL
  -- , findIndicesL
  -- , findIndexR
  -- , findIndicesR
  --   -- * Folds
  --   -- | General folds are available via the 'Foldable' instance of 'Seq'.
  -- , foldMapWithIndex
  -- , foldlWithIndex
  -- , foldrWithIndex
  --   -- * Transformations
  -- , mapWithIndex
  -- , traverseWithIndex
  -- , reverse
  -- , intersperse
  -- ** Zips and unzip
  , zip
  , zipWith
  , zip3
  , zipWith3
  , zip4
  , zipWith4
  , unzip
  , unzipWith
  ) where

import           Control.Applicative
import           Data.Bifunctor
import           Data.Functor.Apply
import           Data.List.NonEmpty  (NonEmpty(..))
import           Data.Sequence       (Seq(..))
import           Data.These
import           Prelude hiding      (length, scanl, scanl1, scanr, scanr1, splitAt, zip, zipWith, zip3, zipWith3, unzip, replicate, filter)
import qualified Data.Sequence       as Seq

data NESeq a = a :<|| !(Seq a)
  deriving Show

unsnoc :: NESeq a -> (Seq a, a)
unsnoc (x :<|| (xs :|> y)) = (x :<| xs, y)
unsnoc (x :<|| Empty     ) = (Empty   , x)
{-# INLINE unsnoc #-}

pattern (:||>) :: Seq a -> a -> NESeq a
pattern xs :||> x <- (unsnoc->(xs, x))
  where
    (x :<| xs) :||> y = x :<|| (xs :|> y)
    Empty      :||> y = y :<|| Empty
{-# COMPLETE (:||>) #-}

nonEmptySeq :: Seq a -> Maybe (NESeq a)
nonEmptySeq (x :<| xs) = Just $ x :<|| xs
nonEmptySeq Empty      = Nothing
{-# INLINE nonEmptySeq #-}

toSeq :: NESeq a -> Seq a
toSeq (x :<|| xs) = x :<| xs
{-# INLINE toSeq #-}

withNonEmpty :: r -> (NESeq a -> r) -> Seq a -> r
withNonEmpty def f = \case
    x :<| xs -> f (x :<|| xs)
    Empty    -> def
{-# INLINE withNonEmpty #-}

unsafeFromSeq :: Seq a -> NESeq a
unsafeFromSeq (x :<| xs) = x :<|| xs
unsafeFromSeq Empty      = errorWithoutStackTrace "NESeq.unsafeFromSeq: empty seq"
{-# INLINE unsafeFromSeq #-}

singleton :: a -> NESeq a
singleton = (:<|| Seq.empty)
{-# INLINE singleton #-}

(<|) :: a -> NESeq a -> NESeq a
x <| xs = x :<|| toSeq xs
{-# INLINE (<|) #-}

(|>) :: NESeq a -> a -> NESeq a
(x :<|| xs) |> y = x :<|| (xs Seq.|> y)
{-# INLINE (|>) #-}

(><) :: NESeq a -> NESeq a -> NESeq a
(x :<|| xs) >< ys = x :<|| (xs Seq.>< toSeq ys)
{-# INLINE (><) #-}

fromList :: NonEmpty a -> NESeq a
fromList (x :| xs) = x :<|| Seq.fromList xs
{-# INLINE fromList #-}

-- TODO: should this just return a Maybe (NESeq a)?  if so, then what's the
-- point?
replicate :: Int -> a -> NESeq a
replicate n x
    | n < 1     = error "NESeq.replicate: must take a positive integer argument"
    | otherwise = x :<|| Seq.replicate (n - 1) x
{-# INLINE replicate #-}

replicateA :: Applicative f => Int -> f a -> f (NESeq a)
replicateA n x
    | n < 1     = error "NESeq.replicate: must take a positive integer argument"
    | otherwise = liftA2 (:<||) x (Seq.replicateA (n - 1) x)
{-# INLINE replicateA #-}

replicateA1 :: Apply f => Int -> f a -> f (NESeq a)
replicateA1 n x
    | n < 1     = error "NESeq.replicate: must take a positive integer argument"
    | otherwise = case runMaybeApply (Seq.replicateA (n - 1) (MaybeApply (Left x))) of
        Left  xs -> (:<||)    <$> x <.> xs
        Right xs -> (:<|| xs) <$> x
{-# INLINE replicateA1 #-}

replicateM :: Applicative m => Int -> m a -> m (NESeq a)
replicateM = replicateA
{-# INLINE replicateM #-}


iterateN :: Int -> (a -> a) -> a -> NESeq a
iterateN n f x = x :<|| Seq.iterateN (n - 1) f (f x)
{-# INLINE iterateN #-}

unfoldr :: (a -> (b, Maybe a)) -> a -> NESeq b
unfoldr f = go
  where
    go x0 = y :<|| maybe Seq.empty (toSeq . go) x1
      where
        (y, x1) = f x0
{-# INLINE unfoldr #-}

unfoldl :: (a -> (b, Maybe a)) -> a -> NESeq b
unfoldl f = go
  where
    go x0 = maybe Seq.empty (toSeq . go) x1 :||> y
      where
        (y, x1) = f x0
{-# INLINE unfoldl #-}

length :: NESeq a -> Int
length (_ :<|| xs) = 1 + Seq.length xs
{-# INLINE length #-}

scanl :: (a -> b -> a) -> a -> NESeq b -> NESeq a
scanl f y0 (x :<|| xs) = y0 :<|| Seq.scanl f (f y0 x) xs
{-# INLINE scanl #-}

scanl1 :: (a -> a -> a) -> NESeq a -> NESeq a
scanl1 f (x :<|| xs) = withNonEmpty (singleton x) (scanl f x) xs
{-# INLINE scanl1 #-}

scanr :: (a -> b -> b) -> b -> NESeq a -> NESeq b
scanr f y0 (xs :||> x) = Seq.scanr f (f x y0) xs :||> y0
{-# INLINE scanr #-}

scanr1 :: (a -> a -> a) -> NESeq a -> NESeq a
scanr1 f (xs :||> x) = withNonEmpty (singleton x) (scanr f x) xs
{-# INLINE scanr1 #-}

tails :: NESeq a -> NESeq (NESeq a)
tails xs@(_ :<|| ys) = withNonEmpty (singleton xs) ((xs <|) . tails) ys
{-# INLINABLE tails #-}

inits :: NESeq a -> NESeq (NESeq a)
inits xs@(ys :||> _) = withNonEmpty (singleton xs) ((|> xs) . inits) ys
{-# INLINABLE inits #-}

chunksOf :: Int -> NESeq a -> NESeq (NESeq a)
chunksOf n = go
  where
    go xs = case splitAt n xs of
      This  ys    -> singleton ys
      That     _  -> e
      These ys zs -> ys <| go zs
    e = error "chunksOf: A non-empty sequence can only be broken up into positively-sized chunks."
{-# INLINABLE chunksOf #-}

takeWhileL :: (a -> Bool) -> NESeq a -> Seq a
takeWhileL p (x :<|| xs)
    | p x       = x Seq.<| Seq.takeWhileL p xs
    | otherwise = Seq.empty
{-# INLINE takeWhileL #-}

takeWhileR :: (a -> Bool) -> NESeq a -> Seq a
takeWhileR p (xs :||> x)
    | p x       = Seq.takeWhileR p xs Seq.|> x
    | otherwise = Seq.empty
{-# INLINE takeWhileR #-}

dropWhileL :: (a -> Bool) -> NESeq a -> Seq a
dropWhileL p xs0@(x :<|| xs)
    | p x       = Seq.dropWhileL p xs
    | otherwise = toSeq xs0
{-# INLINE dropWhileL #-}

dropWhileR :: (a -> Bool) -> NESeq a -> Seq a
dropWhileR p xs0@(xs :||> x)
    | p x       = Seq.dropWhileR p xs
    | otherwise = toSeq xs0
{-# INLINE dropWhileR #-}

spanl :: (a -> Bool) -> NESeq a -> These (NESeq a) (NESeq a)
spanl p xs0@(x :<|| xs)
    | p x       = case (nonEmptySeq ys, nonEmptySeq zs) of
        (Nothing , Nothing ) -> This  (singleton x)
        (Just _  , Nothing ) -> This  xs0
        (Nothing , Just zs') -> These (singleton x) zs'
        (Just ys', Just zs') -> These (x <| ys')    zs'
    | otherwise = That xs0
  where
    (ys, zs) = Seq.spanl p xs
{-# INLINABLE spanl #-}

spanr :: (a -> Bool) -> NESeq a -> These (NESeq a) (NESeq a)
spanr p xs0@(xs :||> x)
    | p x       = case (nonEmptySeq ys, nonEmptySeq zs) of
        (Nothing , Nothing ) -> That  (singleton x)
        (Just ys', Nothing ) -> These ys'           (singleton x)
        (Nothing , Just _  ) -> That  xs0
        (Just ys', Just zs') -> These ys'           (zs' |> x)
    | otherwise = That xs0
  where
    (ys, zs) = Seq.spanr p xs
{-# INLINABLE spanr #-}

breakl :: (a -> Bool) -> NESeq a -> These (NESeq a) (NESeq a)
breakl p = spanl (not . p)
{-# INLINE breakl #-}

breakr :: (a -> Bool) -> NESeq a -> These (NESeq a) (NESeq a)
breakr p = spanr (not . p)
{-# INLINE breakr #-}

partition :: (a -> Bool) -> NESeq a -> These (NESeq a) (NESeq a)
partition p xs0@(x :<|| xs) = case (nonEmptySeq ys, nonEmptySeq zs) of
    (Nothing , Nothing )
      | p x       -> This  (singleton x)
      | otherwise -> That                (singleton x)
    (Just ys', Nothing )
      | p x       -> This  xs0
      | otherwise -> These ys'           (singleton x)
    (Nothing, Just zs' )
      | p x       -> These (singleton x) zs'
      | otherwise -> That                xs0
    (Just ys', Just zs')
      | p x       -> These (x <| ys')    zs'
      | otherwise -> These ys'           (x <| zs')
  where
    (ys, zs) = Seq.partition p xs
{-# INLINABLE partition #-}

filter :: (a -> Bool) -> NESeq a -> Seq a
filter p (x :<|| xs)
    | p x       = x Seq.<| Seq.filter p xs
    | otherwise = Seq.filter p xs
{-# INLINE filter #-}






splitAt :: Int -> NESeq a -> These (NESeq a) (NESeq a)
splitAt 0 xs0             = That xs0
splitAt n xs0@(x :<|| xs) = case (nonEmptySeq ys, nonEmptySeq zs) of
    (Nothing , Nothing ) -> This  (singleton x)
    (Just _  , Nothing ) -> This  xs0
    (Nothing , Just zs') -> These (singleton x) zs'
    (Just ys', Just zs') -> These (x <| ys')    zs'
  where
    (ys, zs) = Seq.splitAt (n - 1) xs
{-# INLINABLE splitAt #-}

zip :: NESeq a -> NESeq b -> NESeq (a, b)
zip (x :<|| xs) (y :<|| ys) = (x, y) :<|| Seq.zip xs ys
{-# INLINE zip #-}

zipWith :: (a -> b -> c) -> NESeq a -> NESeq b -> NESeq c
zipWith f (x :<|| xs) (y :<|| ys) = f x y :<|| Seq.zipWith f xs ys
{-# INLINE zipWith #-}

zip3 :: NESeq a -> NESeq b -> NESeq c -> NESeq (a, b, c)
zip3 (x :<|| xs) (y :<|| ys) (z :<|| zs) = (x, y, z) :<|| Seq.zip3 xs ys zs
{-# INLINE zip3 #-}

zipWith3 :: (a -> b -> c -> d) -> NESeq a -> NESeq b -> NESeq c -> NESeq d
zipWith3 f (x :<|| xs) (y :<|| ys) (z :<|| zs) = f x y z :<|| Seq.zipWith3 f xs ys zs
{-# INLINE zipWith3 #-}

zip4 :: NESeq a -> NESeq b -> NESeq c -> NESeq d -> NESeq (a, b, c, d)
zip4 (x :<|| xs) (y :<|| ys) (z :<|| zs) (r :<|| rs) = (x, y, z, r) :<|| Seq.zip4 xs ys zs rs
{-# INLINE zip4 #-}

zipWith4 :: (a -> b -> c -> d -> e) -> NESeq a -> NESeq b -> NESeq c -> NESeq d -> NESeq e
zipWith4 f (x :<|| xs) (y :<|| ys) (z :<|| zs) (r :<|| rs) = f x y z r :<|| Seq.zipWith4 f xs ys zs rs
{-# INLINE zipWith4 #-}

unzip :: NESeq (a, b) -> (NESeq a, NESeq b)
unzip ((x, y) :<|| xys) = bimap (x :<||) (y :<||) . Seq.unzip $ xys
{-# INLINE unzip #-}

unzipWith :: (a -> (b, c)) -> NESeq a -> (NESeq b, NESeq c)
unzipWith f (x :<|| xs) = bimap (y :<||) (z :<||) . Seq.unzipWith f $ xs
  where
    (y, z) = f x
{-# INLINE unzipWith #-}
