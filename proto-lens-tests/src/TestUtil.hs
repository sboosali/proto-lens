-- Copyright 2016 Google Inc. All Rights Reserved.
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

{-# LANGUAGE ScopedTypeVariables #-}
module TestUtil(
    testMain,
    Test,
    serializeTo,
    deserializeFrom,
    readFrom,
    Data(..),
    tagged,
    varInt,
    keyed,
    keyedDoc,
    braced,
    testProperty,
    textRoundTripProperty,
    wireRoundTripProperty,
    MessageProperty,
    roundTripTest,
    TypedTest(runTypedTest),
    PrettyPrint.Doc,
    PrettyPrint.vcat,
    (PrettyPrint.$+$),
    ) where

import Data.ProtoLens
import Data.ProtoLens.Arbitrary

import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as L
import qualified Data.Text.Lazy as LT
import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.API (Test)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit ((@=?), assertBool)
import Data.Either (isLeft)
import Data.Bits (shiftL, shiftR, (.|.), (.&.))
import Data.Foldable (foldMap)
import qualified Data.Text.Lazy as TL
import Data.Monoid ((<>))
import Data.Word (Word32, Word64)
import qualified Text.PrettyPrint as PrettyPrint
import Text.PrettyPrint
    ( char
    , colon
    , nest
    , renderStyle
    , style
    , lineLength
    , (<+>)
    , ($+$)
    )

testMain :: [Test] -> IO ()
testMain = defaultMain

serializeTo :: (Show a, Eq a, Message a)
            => String -> a -> PrettyPrint.Doc -> Builder.Builder -> Test
serializeTo name x text bs = testCase name $ do
    let bs' = L.toStrict $ Builder.toLazyByteString bs
    bs' @=? encodeMessage x
    x @=? decodeMessageOrDie bs'
    let text' = show text
    -- For consistency in the tests, make them put each field and submessage on
    -- a separate line.
    text' @=? renderStyle style {lineLength = 1} (pprintMessage x)
    x @=? readMessageOrDie (LT.pack text')

deserializeFrom :: (Show a, Eq a, Message a)
                => String -> Maybe a -> Builder.Builder -> Test
deserializeFrom name x bs = testCase name $ case x of
    -- Check whether or not it failed without worrying about the exact error
    -- message.
    Nothing -> assertBool ("Expected failure, found " ++ show y) $ isLeft y
    Just x' -> Right x' @=? y
  where
    y = decodeMessage $ L.toStrict $ Builder.toLazyByteString bs

type MessageProperty a = ArbitraryMessage a -> Bool

wireRoundTripProperty :: (Message a, Eq a) => MessageProperty a
wireRoundTripProperty (ArbitraryMessage msg) =
    let msg' = (decodeMessage . encodeMessage) msg
    in msg' == Right msg

textRoundTripProperty :: (Message a, Eq a) => MessageProperty a
textRoundTripProperty (ArbitraryMessage msg) =
    let msg' = (readMessage . TL.pack . showMessage) msg
    in msg' == Right msg

newtype TypedTest a = TypedTest { runTypedTest :: Test }

roundTripTest :: forall a . (Show a, Message a, Eq a) => String -> TypedTest a
roundTripTest name = TypedTest $ testGroup name
    [ testProperty "wire" (wireRoundTripProperty :: MessageProperty a)
    , testProperty "text" (textRoundTripProperty :: MessageProperty a)
    ]

readFrom :: (Show a, Eq a, Message a)
         => String -> Maybe a -> LT.Text -> Test
readFrom name x text = testCase name $ case x of
    -- Check whether or not it failed without worrying about the exact error
    -- message.
    Nothing -> assertBool ("Expected failure, found " ++ show y) $ isLeft y
    Just x' -> Right x' @=? y
  where y = readMessage text

varInt :: Word64 -> Builder.Builder
varInt n
    | n < 128 = Builder.word8 (fromIntegral n)
    | otherwise = Builder.word8 (fromIntegral $ n .&. 127 .|. 128)
                      <> varInt (n `shiftR` 7)

data Data
  = VarInt Word64
  | Fixed64 Word64
  | Fixed32 Word32
  | Lengthy Builder.Builder
  | Group [(Word64, Data)]

-- | Build the binary representation of a proto field.
-- Note that this code should be separate from anything in Data.ProtoLens.*,
-- so it can unit test the encoding code.
tagged :: Word64 -> Data -> Builder.Builder
tagged t (VarInt w) = varInt (t `shiftL` 3 .|. 0) <> varInt w
tagged t (Fixed64 w) = varInt (t `shiftL` 3 .|. 1) <> Builder.word64LE w
tagged t (Fixed32 w) = varInt (t `shiftL` 3 .|. 5) <> Builder.word32LE w
tagged t (Lengthy bs) = let
    bs' = Builder.toLazyByteString bs
    in varInt (t `shiftL` 3 .|. 2) <> varInt (fromIntegral $ L.length bs')
        <> Builder.lazyByteString bs'
tagged t (Group tvs) =
    varInt (t `shiftL` 3 .|. 3)
    <> foldMap (uncurry tagged) tvs
    <> varInt (t `shiftL` 3 .|. 4)

-- | Utility to generate the text format for a single, non-message field.
keyed :: Show a => String -> a -> PrettyPrint.Doc
keyed k v = keyedDoc k (PrettyPrint.text (show v))

-- | Utility to generate the text format for a single, non-message field
-- which doesn't correspond to a 'Show' instance.
keyedDoc :: String -> PrettyPrint.Doc -> PrettyPrint.Doc
keyedDoc k v = PrettyPrint.text k <> (colon <+> v)

-- | Utility to generate the text format for a submessage.
braced :: String -> PrettyPrint.Doc -> PrettyPrint.Doc
braced k v = (PrettyPrint.text k <+> char '{')
              $+$ nest 2 v
              $+$ PrettyPrint.char '}'
