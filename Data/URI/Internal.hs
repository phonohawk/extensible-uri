{-# LANGUAGE
    BangPatterns
  , CPP
  , FlexibleInstances
  , ScopedTypeVariables
  , UnicodeSyntax
  #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Data.URI.Internal
    ( isUnreserved
    , isPctEncoded
    , isHexDigit_w8
    , isSubDelim
    , inRange_w8

    , atoi
    , htoi

    , countV
    , countUpToV
    , countUpTo
    , countUpTo1
    , finishOff

    , bHex
    )
    where
import Blaze.ByteString.Builder (Builder, Write)
import qualified Blaze.ByteString.Builder as BB
import qualified Blaze.ByteString.Builder.Char8 as BB
import Control.Applicative
import Control.Applicative.Unicode
import Control.DeepSeq
import Control.Monad
import Control.Monad.Primitive
import Control.Monad.Unicode
import qualified Data.Attoparsec as B
import Data.Attoparsec.Char8
import Data.Bits
import Data.CaseInsensitive as CI
import Data.Char
import Data.Hashable
import Data.Maybe
import Data.Monoid.Unicode
import Data.Semigroup
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector.Fusion.Util
import qualified Data.Vector.Generic as GV
import qualified Data.Vector.Storable as SV
import Data.Vector.Storable.ByteString.Char8 (ByteString)
import qualified Data.Vector.Storable.ByteString.Char8 as C8
import Data.Vector.Storable.ByteString.Internal (c2w)
import qualified Data.Vector.Unboxed as UV
import Data.Word
import Foreign.ForeignPtr
import Foreign.Storable
import Numeric.Natural
import Prelude.Unicode
#if defined(MIN_VERSION_QuickCheck)
import Test.QuickCheck.Arbitrary
import Test.QuickCheck.Gen
#endif

isUnreserved ∷ Char → Bool
{-# INLINE isUnreserved #-}
isUnreserved = inClass "a-zA-Z0-9._~-"

isPctEncoded ∷ Char → Bool
{-# INLINE isPctEncoded #-}
isPctEncoded = inClass "%a-fA-F0-9"

isHexDigit_w8 ∷ Word8 → Bool
{-# INLINE isHexDigit_w8 #-}
isHexDigit_w8 = B.inClass "a-fA-F0-9"

isSubDelim ∷ Char → Bool
{-# INLINE isSubDelim #-}
isSubDelim = inClass "!$&'()*+,;="

inRange_w8 ∷ Char → Char → Word8 → Bool
{-# INLINE inRange_w8 #-}
inRange_w8 x y w
    = c2w x ≤ w ∧ w ≤ c2w y

atoi ∷ Integral n ⇒ Word8 → n
{-# INLINE atoi #-}
atoi = subtract 0x30 ∘ fromIntegral

htoi ∷ Integral n ⇒ Word8 → n
{-# INLINEABLE htoi #-}
htoi w | w ≥ 0x30 ∧ w ≤ 0x39 = fromIntegral (w - 0x30) -- '0'..'9'
       | w ≥ 0x61            = fromIntegral (w - 0x57) -- 'a'..'f'
       | otherwise           = fromIntegral (w - 0x37) -- 'A'..'F'

countV ∷ (GV.Vector v α, Functor m, Monad m) ⇒ Int → m α → m (v α)
{-# INLINE countV #-}
countV = ((GV.fromList <$>) ∘) ∘ count

countUpToV ∷ (GV.Vector v α, Alternative f) ⇒ Int → f α → f (v α)
{-# INLINE countUpToV #-}
countUpToV = ((GV.fromList <$>) ∘) ∘ countUpTo

countUpTo ∷ Alternative f ⇒ Int → f α → f [α]
{-# INLINEABLE countUpTo #-}
countUpTo 0 _ = pure []
countUpTo n p = ((:) <$> p ⊛ countUpTo (n-1) p) <|> pure []

countUpTo1 ∷ Alternative f ⇒ Int → f α → f [α]
{-# INLINE countUpTo1 #-}
countUpTo1 n p = (:) <$> p ⊛ countUpTo (n-1) p

finishOff ∷ Parser α → Parser α
{-# INLINE finishOff #-}
finishOff = ((endOfInput *>) ∘ pure =≪)

bHex ∷ ∀n. (Integral n, Bits n) ⇒ n → Builder
{-# INLINE bHex #-}
bHex = BB.fromWrite ∘ fromMaybe (BB.writeChar '0') ∘ go Nothing
    where
      go ∷ Maybe Write → n → Maybe Write
      {-# INLINEABLE go #-}
      go !w  0 = w
      go !w !n = go (Just (BB.writeWord8 hex) ⊕ w) (n `shiftR` 4)
          where
            nibble ∷ Word8
            nibble = fromIntegral n .&. 0xF

            hex ∷ Word8
            hex | nibble < 10 = 0x30 + nibble
                | otherwise   = 0x57 + nibble

-- FIXME: Remove this when the vector starts providing Hashable
-- instances.
instance (Hashable α, Storable α) ⇒ Hashable (SV.Vector α) where
    {-# INLINEABLE hashWithSalt #-}
    hashWithSalt salt sv
        = unsafeInlineIO ∘ withForeignPtr fp $
          \p → hashPtrWithSalt p (fromIntegral len) salt
        where
          (fp, n) = SV.unsafeToForeignPtr0 sv
          len     = n ⋅ sizeOf ((⊥) ∷ α)

-- FIXME: Remove this when the vector starts providing Hashable
-- instances. Unboxed vectors don't expose their internal
-- representation (ByteArray#) so we can't implement an efficient
-- instance.
instance (Hashable α, UV.Unbox α) ⇒ Hashable (UV.Vector α) where
    {-# INLINE hashWithSalt #-}
    hashWithSalt = UV.foldl' hashWithSalt

-- FIXME: Remove this when the nats starts providing Hashable instance.
instance Hashable Natural where
    {-# INLINE hashWithSalt #-}
    hashWithSalt salt n
        = salt `hashWithSalt` toInteger n

-- FIXME: Remove this when the nats starts providing NFData instance.
instance NFData Natural

-- FIXME: Remove this when the vector-bytestring starts providing
-- FoldCase instance.
instance FoldCase ByteString where
    {-# INLINE foldCase #-}
    foldCase = C8.map toLower

-- FIXME: Remove this when the Id starts providing Applicative
-- instance.
instance Applicative Id where
    {-# INLINE pure #-}
    pure = return
    {-# INLINE (<*>) #-}
    (<*>) = ap

-- FIXME: Remove this when the vector-bytestring starts providing
-- Semigroup instance.
instance Semigroup ByteString where
    {-# INLINE CONLIKE (<>) #-}
    (<>) = (⊕)

#if defined(MIN_VERSION_QuickCheck)
-- FIXME: Remove this when the vector-bytestring starts providing
-- Arbitrary instance.
instance Arbitrary ByteString where
    arbitrary = C8.pack <$> listOf arbitrary
    shrink    = (C8.pack <$>) ∘ shrink ∘ C8.unpack

-- FIXME: Remove this when the vector-bytestring starts providing
-- CoArbitrary instance.
instance CoArbitrary ByteString where
    coarbitrary = coarbitrary ∘ C8.unpack

-- FIXME: Remove this when the case-insensitive starts providing
-- Arbitrary instance.
instance (Arbitrary α, FoldCase α) ⇒ Arbitrary (CI α) where
    arbitrary = CI.mk <$> arbitrary
    shrink    = (CI.mk <$>) ∘ shrink ∘ CI.original

-- FIXME: Remove this when the case-insensitive starts providing
-- CoArbitrary instance.
instance CoArbitrary α ⇒ CoArbitrary (CI α) where
    coarbitrary = coarbitrary ∘ CI.original

-- FIXME: Remove this when the nats starts providing Arbitrary
-- instance.
instance Arbitrary Natural where
    arbitrary = fromInteger ∘ abs <$> arbitrary
    shrink    = (fromInteger <$>) ∘ shrink ∘ toInteger

-- FIXME: Remove this when the nats starts providing CoArbitrary
-- instance.
instance CoArbitrary Natural where
    coarbitrary = coarbitrary ∘ toInteger

-- FIXME: Remove this when the text starts providing Arbitrary
-- instance.
instance Arbitrary Text where
    arbitrary = T.pack <$> listOf arbitrary
    shrink    = (T.pack <$>) ∘ shrink ∘ T.unpack

-- FIXME: Remove this when the text starts providing CoArbitrary
-- instance.
instance CoArbitrary Text where
    coarbitrary = coarbitrary ∘ T.unpack
#endif
