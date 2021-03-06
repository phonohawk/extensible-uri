{-# LANGUAGE
    CPP
  , DeriveDataTypeable
  , FlexibleContexts
  , FlexibleInstances
  , GeneralizedNewtypeDeriving
  , UnicodeSyntax
  , ViewPatterns
  #-}
module Data.URI.Internal.UserInfo
    ( UserInfo(..)
    , parser
    , fromByteString
    , toBuilder
    )
    where
import Blaze.ByteString.Builder (Builder)
import qualified Blaze.ByteString.Builder.ByteString as BB
import Codec.URI.PercentEncoding (DelimitedByteString)
import qualified Codec.URI.PercentEncoding as PE
import Control.Applicative
import Control.DeepSeq
import Control.Failure
import Data.Attoparsec.Char8
import Data.Data
import Data.Hashable
import Data.Monoid
import Data.Semigroup
import Data.String
import Data.URI.Internal
import Data.Vector.Storable.ByteString (ByteString)
import qualified Data.Vector.Storable.ByteString.Char8 as C8
import Data.Vector.Storable.ByteString.Legacy
import Prelude hiding (takeWhile)
import Prelude.Unicode
#if defined(MIN_VERSION_QuickCheck)
import Test.QuickCheck.Arbitrary
#endif

-- |The userinfo subcomponent may consist of a user name and,
-- optionally, scheme-specific information about how to gain
-- authorization to access the resource. See:
-- <http://tools.ietf.org/html/rfc3986#section-3.2.1>
newtype UserInfo = UserInfo { unUserInfo ∷ DelimitedByteString }
    deriving ( Eq
             , Hashable
             , NFData
             , Ord
             , Semigroup
             , Typeable
             , Monoid
#if defined(MIN_VERSION_QuickCheck)
             , Arbitrary
             , CoArbitrary
#endif
             )

-- |For testing purpose only.
instance Show UserInfo where
    show = C8.unpack ∘ PE.encode ((¬) ∘ isSafeInUserInfo) ∘ unUserInfo

-- |'fromString' constructs an 'UserInfo' from a 'String'. Throws a
-- runtime exception for invalid userinfo.
instance IsString UserInfo where
    {-# INLINEABLE fromString #-}
    fromString (toLegacyByteString ∘ C8.pack → str)
        = case parseOnly (finishOff parser) str of
            Right s → s
            Left  e → error e

-- |'Parser' for 'UserInfo'.
parser ∷ Parser UserInfo
{-# INLINEABLE parser #-}
parser = do src ← takeWhile isAllowed
            case PE.decode (≡ ':') (fromLegacyByteString src) of
              Right dst → pure $ UserInfo dst
              Left  e   → fail $ show (e ∷ PE.DecodeError)
         <?>
         "userinfo"
    where
      isAllowed ∷ Char → Bool
      {-# INLINE isAllowed #-}
      isAllowed c = isUnreserved c ∨
                    isPctEncoded c ∨
                    isSubDelim   c ∨
                    ':' ≡        c

-- |Try to parse an 'UserInfo' from an ascii string.
fromByteString ∷ Failure String f ⇒ ByteString → f UserInfo
{-# INLINE fromByteString #-}
fromByteString = either failure return        ∘
                 parseOnly (finishOff parser) ∘
                 toLegacyByteString

-- |Create a 'Builder' from an 'UserInfo'.
toBuilder ∷ UserInfo → Builder
{-# INLINE toBuilder #-}
toBuilder = BB.fromByteString                  ∘
            toLegacyByteString                 ∘
            PE.encode ((¬) ∘ isSafeInUserInfo) ∘
            unUserInfo

isSafeInUserInfo ∷ Char → Bool
{-# INLINE isSafeInUserInfo #-}
isSafeInUserInfo c = isUnreserved c ∨ isSubDelim c
