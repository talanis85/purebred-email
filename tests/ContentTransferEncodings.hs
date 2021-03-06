{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module ContentTransferEncodings where

import Data.Word

import Control.Lens (clonePrism, preview, review)
import qualified Data.ByteString as B

import Test.Tasty
import Test.Tasty.QuickCheck
import Test.QuickCheck.Instances ()

import Data.MIME.Base64 (contentTransferEncodingBase64)
import Data.MIME.QuotedPrintable
import Data.MIME.Types


properties :: TestTree
properties = localOption (QuickCheckMaxSize 1000) $
  testGroup "codec properties"
    [ testGroup "Content-Transfer-Encoding properties"
      [ testProperty "base64 round-trip"
          (prop_roundtrip contentTransferEncodingBase64)
      , testProperty "quoted-printable round-trip"
          (prop_roundtrip contentTransferEncodingQuotedPrintable)
      , testProperty "base64 line length <= 76"
          (prop_linelength contentTransferEncodingBase64)
      , testProperty "quoted-printable line length <= 76"
          (prop_linelength contentTransferEncodingQuotedPrintable)
      ]
    , testGroup "encoded-word codec properties"
      [ testProperty "Q round-trip" (prop_roundtrip q)
      , testProperty "Q does not contain spaces" (prop_notElem q 32 {- ' ' -})
      ]
    ]


prop_roundtrip :: ContentTransferEncoding -> B.ByteString -> Bool
prop_roundtrip p s = preview (clonePrism p) (review (clonePrism p) s) == Just s

prop_linelength :: ContentTransferEncoding -> B.ByteString -> Property
prop_linelength p s =
  let
    encoded = review (clonePrism p) s
    prop = all ((<= 76) . B.length) (splitOnCRLF encoded)
  in
#if ! MIN_VERSION_QuickCheck(2,12,0)
    cover (B.length encoded > 100) 50 "long output" prop
#else
    checkCoverage $ cover 50 (B.length encoded > 100) "long output" prop
#endif

prop_notElem :: EncodedWordEncoding -> Word8 -> B.ByteString -> Bool
prop_notElem enc c = B.notElem c . review (clonePrism enc)

splitOnCRLF :: B.ByteString -> [B.ByteString]
splitOnCRLF s =
  let (l, r) = B.breakSubstring "\r\n" s
  in
    if B.null r
      then [l]
      else l : splitOnCRLF (B.drop 2 r)
