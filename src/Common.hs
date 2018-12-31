{-| Common data types and combinators. We declare a fair number of monomorphic
    types because otherwise fields cannot be unpacked.
-}

module Common where

import Data.Bits
import Data.Text.Short (ShortText)
import Data.Time.Clock
import GHC.Magic (runRW#)
import GHC.Types (IO(..))
import Text.Megaparsec.Pos (SourcePos)
import Control.Monad.Except

type Unfoldable = Bool

data Icit = Expl | Impl deriving (Eq, Show)

-- | If-then-else for 'Icit'.
icit :: Icit -> a -> a -> a
icit Impl i e = i
icit Expl i e = e
{-# inline icit #-}

-- | Lazy boxed identity monad, used for controlled thunk creation.
data Box a = Box ~a

-- | Names used for definitions and binders.
type Name = ShortText

-- | De Bruijn indices. Used in syntax.
type Ix = Int

-- | De Bruijn levels. Used in values.
type Lvl = Int

data NameOrIcit = NOName {-# unpack #-} Name | NOImpl | NOExpl deriving Show

data Posed a = Posed SourcePos a
  -- deriving Show

instance Show a => Show (Posed a) where
  showsPrec d (Posed _ b) = showsPrec d b

posOf (Posed p _) = p
unPosed (Posed _ a) = a
{-# inline posOf #-}
{-# inline unPosed #-}

data Named a = Named {-# unpack #-} Name a deriving (Show, Functor)
nameOf (Named x _) = x
unNamed (Named _ a) = a
{-# inline nameOf #-}
{-# inline unNamed #-}

-- Bit-packed pair of 32 bit integers.
--------------------------------------------------------------------------------

newtype Int2 = MkInt2 Int deriving (Eq, Ord)

instance Show Int2 where show (Int2 x y) = show (x, y)

unpackInt2 :: Int2 -> (Int, Int)
unpackInt2 (MkInt2 x) = (unsafeShiftR x 32, x .&. 0xFFFFFFFF)
{-# inline unpackInt2 #-}

pattern Int2 :: Int -> Int -> Int2
pattern Int2 x y <- (unpackInt2 -> (x, y)) where
  Int2 x y = MkInt2 (unsafeShiftL x 32 .|. y)
{-# complete Int2 #-}

--------------------------------------------------------------------------------


-- | Indices for metavariables. Consists of two 32-bit numbers, one is an index
--   for the top context, the other indexes the meta context at that
--   entry. NOTE: the following only works on 64-bit systems. TODO: rewrite in
--   32-bit compatible way.
newtype Meta = MkMeta Int2 deriving (Eq, Ord)
pattern Meta :: Lvl -> Lvl -> Meta
pattern Meta x y = MkMeta (Int2 x y)
{-# complete Meta #-}

metaTopLvl :: Meta -> Lvl
metaTopLvl (Meta i _) = i
{-# inline metaTopLvl #-}

metaLocalLvl :: Meta -> Lvl
metaLocalLvl (Meta _ j) = j
{-# inline metaLocalLvl #-}

instance Show Meta where show (Meta x y) = show (x, y)

--------------------------------------------------------------------------------

data Names = NNil | NSnoc Names {-# unpack #-} Name deriving Show

lookupName :: Ix -> Names -> Name
lookupName = go where
  go 0 (NSnoc _ n) = n
  go n (NSnoc ns _) = go (n - 1) ns
  go _ _ = error "lookupName: impossible"

namesLength :: Names -> Int
namesLength = go 0 where
  go l NNil = l
  go l (NSnoc ns _) = go (l + 1) ns

-- | The same as 'unsafeDupablePerformIO'.
runIO :: IO a -> a
runIO (IO f) = runRW# (\s -> case f s of (# _, a #) -> a)
{-# inline runIO #-}

-- | A partial mapping from local levels to local levels.
data Renaming = RNil | RCons Lvl Lvl Renaming

-- | Returns (-1) on error.
applyRen :: Renaming -> Ix -> Ix
applyRen (RCons k v ren) x
  | x == k    = v
  | otherwise = applyRen ren x
applyRen RNil _ = (-1)


data Rigidity = Rigid | Flex deriving Show

meld :: Rigidity -> Rigidity -> Rigidity
meld Flex  _ = Flex
meld Rigid r = r
{-# inline meld #-}

-- | Strict pair type.
data T2 a b = T2 a b deriving (Eq, Show)

proj1 (T2 a _) = a
proj2 (T2 _ b) = b
{-# inline proj1 #-}
{-# inline proj2 #-}

data T3 a b c = T3 a b c deriving (Eq, Show)

-- | Time an IO computation. Result is forced to whnf.
timed :: IO a -> IO (a, NominalDiffTime)
timed a = do
  t1  <- getCurrentTime
  res <- a
  t2  <- getCurrentTime
  pure (res, diffUTCTime t2 t1)
{-# inline timed #-}

-- | Time a lazy pure value. Result is forced to whnf.
timedPure :: a -> IO (a, NominalDiffTime)
timedPure ~a = do
  t1  <- getCurrentTime
  let res = a
  t2  <- getCurrentTime
  pure (res, diffUTCTime t2 t1)
{-# inline timedPure #-}

finally :: MonadError e m => m a -> m b -> m a
finally ma mb = do
  a <- ma `catchError` \e -> mb >> throwError e
  mb
  pure a
{-# inline finally #-}
