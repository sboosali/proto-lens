-- Copyright 2016 Google Inc. All Rights Reserved.
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

{-# LANGUAGE OverloadedStrings, OverloadedLists #-}
module Main where

import Proto.Map
import Data.ProtoLens
import Lens.Family2 ((&), (.~))
import qualified Data.ByteString.Char8 as C
import Data.ByteString.Builder (Builder, byteString)
import Data.Monoid (mempty, (<>))
import Data.Word (Word64)

import TestUtil

defFoo :: Foo
defFoo = def

entry :: Word64 -> String -> Builder
entry k v = tagged 1 $ Lengthy $ tagged 1 (VarInt k)
                                <> taggedValue v

taggedValue :: String -> Builder
taggedValue = tagged 2 . Lengthy . byteString . C.pack

kvPair :: (Show k, Show v) => k -> v -> Doc
kvPair k v = keyed "key" k $+$ keyed "value" v


-- Note how OverloadedLists work here in the "bar" field.
-- For proto-lens, it resolves to a (Map Int32 Text).
main = testMain
    [ serializeTo "default" defFoo "" mempty
    , serializeTo "singleton"
        (defFoo & bar .~ [(42, "qwerty")])
        (braced "bar" $ kvPair 42 "qwerty")
        (entry 42 "qwerty")
    , serializeTo "moreElements"
        (defFoo & bar .~ [(17, "abc"), (42, "qwerty")])
        (braced "bar" (kvPair 17 "abc") $+$ braced "bar" (kvPair 42 "qwerty"))
        (entry 17 "abc" <> entry 42 "qwerty")
    -- Check that we can tolerate missing keys and values.
    , deserializeFrom "missing key"
        (Just $ defFoo & bar .~ [(0, "abc")])
        $ tagged 1 $ Lengthy $ taggedValue "abc"
    , deserializeFrom "missing value"
        (Just $ defFoo & bar .~ [(42, "")])
        $ tagged 1 $ Lengthy $ tagged 1 $ VarInt 42
    , runTypedTest (roundTripTest "roundtrip" :: TypedTest Foo)
    ]
