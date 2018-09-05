{-# OPTIONS_GHC -fno-warn-type-defaults #-}
{-# LANGUAGE OverloadedStrings #-}
module Headers where

import Control.Lens
import qualified Data.ByteString.Char8 as BC
import Data.Attoparsec.ByteString.Char8 (parseOnly)

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit ((@=?), (@?=), testCase, Assertion)

import Data.MIME


unittests :: TestTree
unittests = testGroup "Headers"
  [ parsesMailboxesSuccessfully
  , parsesAddressesSuccessfully
  , ixAndAt
  , contentTypeTests
  , parameterTests
  ]

-- | Note some examples are taken from https://tools.ietf.org/html/rfc3696#section-3
mailboxes :: [(String, Either String Mailbox -> Assertion, BC.ByteString)]
mailboxes =
    [ ( "address with FQDN"
      , (Right (Mailbox Nothing (AddrSpec "foo" (DomainDotAtom $ pure "bar.com"))) @=?)
      , BC.pack "foo@bar.com")
    , ( "just with a host name"
      , (Right (Mailbox Nothing (AddrSpec "foo" (DomainDotAtom $ pure "bar"))) @=?)
      , BC.pack "foo@bar")
    , ( "domain as IPv4"
      , (Right (Mailbox (Just "roman") (AddrSpec "roman" (DomainLiteral "192.168.1.1"))) @=?)
      , BC.pack "roman <roman@[192.168.1.1]>")
    , ( "domain as IPv6"
      , (Right (Mailbox (Just "roman") (AddrSpec "roman" (DomainLiteral "::1"))) @=?)
      , BC.pack "roman <roman@[::1]>")
    , ( "without TLD"
      , (Right (Mailbox Nothing (AddrSpec "roman" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "roman@host")
    , ( "with quotes in local-part"
      , (Right (Mailbox Nothing (AddrSpec "roman" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "\"roman\"@host")
    , ( "quoted localpart with @"
      , (Right (Mailbox Nothing (AddrSpec "Abc@def" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "\"Abc\\@def\"@host")
    , ( "whitespace in quoted local-part"
      , (Right (Mailbox Nothing (AddrSpec "Mr Whitespace" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "\"Mr Whitespace\"@host")
    , ( "special chars in local-part"
      , (Right (Mailbox Nothing (AddrSpec "customer/department=shipping" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "<customer/department=shipping@host>")
    , ( "special chars in local-part"
      , (Right (Mailbox Nothing (AddrSpec "!def!xyz%abc" (DomainDotAtom $ pure "host"))) @=?)
      , BC.pack "!def!xyz%abc@host")
    , ( "garbled address"
      , (Left "[: not enough input" @=?)
      , BC.pack "fasdf@")
    , ( "wrong: comma in front of domain"
      , (Left "[: Failed reading: satisfy" @=?)
      , BC.pack "foo@,bar,com")
    ]

parsesMailboxesSuccessfully :: TestTree
parsesMailboxesSuccessfully =
    testGroup "parsing mailboxes" $
    (\(desc,f,input) -> testCase desc $ f (parseOnly mailbox input))
    <$> mailboxes

addresses :: [(String, Either String Address -> Assertion, BC.ByteString)]
addresses =
    [ ( "single address"
      , (Right (Single (Mailbox Nothing (AddrSpec "foo" (DomainDotAtom $ pure "bar.com")))) @=?)
      , BC.pack "<foo@bar.com>")
    , ( "group of addresses"
      , (Right
             (Group
                  "Group"
                  [ Mailbox (Just "Mr Foo") (AddrSpec "foo" (DomainDotAtom $ pure "bar.com"))
                  , Mailbox (Just "Mr Bar") (AddrSpec "bar" (DomainDotAtom $ pure "bar.com"))]) @=?)
      , BC.pack "Group: \"Mr Foo\" <foo@bar.com>, \"Mr Bar\" <bar@bar.com>;")
    , ( "group of undisclosed recipients"
      , (Right (Group "undisclosed-recipients" []) @=?)
      , BC.pack "undisclosed-recipients:;")
    ]

parsesAddressesSuccessfully :: TestTree
parsesAddressesSuccessfully =
    testGroup "parsing addresses" $
    (\(desc,f,input) -> testCase desc $ f (parseOnly address input))
    <$> addresses

-- | Sanity check Ixed and At instances
ixAndAt :: TestTree
ixAndAt = testGroup "Ix and At instances"
  [ testCase "set header" $
      set (at "content-type") (Just "text/plain") empty @?= textPlain
  , testCase "set header (multiple)" $
      set (at "content-type") (Just "text/html") multi
      @?= Headers [("Content-Type", "text/html"), ("Content-Type", "text/plain")]
  , testCase "update header (case differs)" $
      set (at "content-type") (Just "text/html") textPlain @?= textHtml
  , testCase "delete header (one)" $
      sans "content-type" textPlain @?= empty
  , testCase "delete header (one)" $
      sans "content-type" textPlain @?= empty
  , testCase "delete header (multiple)" $
      sans "content-type" multi @?= textPlain
  , testCase "delete header (no match)" $
      sans "subject" textPlain @?= textPlain
  , testCase "ix targets all" $
      toListOf (ix "content-type") multi @?= ["foo/bar", "text/plain"]
  ]


contentTypeTests :: TestTree
contentTypeTests = testGroup "Content-Type header"
  [ testCase "parsing header" $
      view contentType textHtml @?= ctTextHtml
  , testCase "no header yields default" $
      view contentType empty @?= defaultContentType
  , testCase "set when undefined" $
      set contentType ctTextHtml empty @?= textHtml
  , testCase "set when defined (update)" $
      set contentType ctTextHtml textPlain @?= textHtml
  , testCase "update undefined content type" $
      over (contentType . parameterList) (("foo","bar"):) empty @?= defaultFoobar
  , testCase "update defined content type" $
      over (contentType . parameterList) (("foo","bar"):) textHtml @?= textHtmlFoobar
  ]
  where
  ctTextHtml = ContentType "text" "html" (Parameters [])

empty, textPlain, textHtml, multi, defaultFoobar, textHtmlFoobar :: Headers
empty = Headers []
textPlain = Headers [("Content-Type", "text/plain")]
textHtml = Headers [("Content-Type", "text/html")]
multi = Headers [("Content-Type", "foo/bar"), ("Content-Type", "text/plain")]
defaultFoobar = Headers [("Content-Type", "text/plain; foo=bar; charset=us-ascii")]
textHtmlFoobar = Headers [("Content-Type", "text/html; foo=bar")]

parameterTests :: TestTree
parameterTests = testGroup "parameter handling"
  [ testCase "RFC 2231 §3 example" $
      view (contentType . parameters . at "url")
        (Headers [("Content-Type", "message/external-body; access-type=URL; URL*0=\"ftp://\"; URL*1=\"cs.utk.edu/pub/moore/bulk-mailer/bulk-mailer.tar\"")])
      @?= Just (ParameterValue Nothing Nothing "ftp://cs.utk.edu/pub/moore/bulk-mailer/bulk-mailer.tar")
  , testCase "RFC 2231 §4 example" $
      view (contentType . parameters . at "title")
        (Headers [("Content-Type", "application/x-stuff; title*=us-ascii'en-us'This%20is%20%2A%2A%2Afun%2A%2A%2A")])
      @?= Just (ParameterValue (Just "us-ascii") (Just "en-us") "This is ***fun***")
  , testCase "RFC 2231 §4.1 example" $
      view (contentType . parameters . at "title")
        (Headers [("Content-Type", "application/x-stuff; title*0*=us-ascii'en'This%20is%20even%20more%20; title*1*=%2A%2A%2Afun%2A%2A%2A%20; title*2=\"isn't it!\"")])
      @?= Just (ParameterValue (Just "us-ascii") (Just "en") "This is even more ***fun*** isn't it!")
  , testCase "set filename parameter in Content-Disposition" $
      set (contentDisposition . parameters . at "filename") (Just (ParameterValue Nothing Nothing "foo.pdf"))
        (Headers [("Content-Disposition", "attachment")])
      @?= Headers [("Content-Disposition", "attachment; filename=foo.pdf")]
  , testCase "unset filename parameter in Content-Disposition" $
      set (contentDisposition . parameters . at "filename") Nothing
        (Headers [("Content-Disposition", "attachment; foo=bar; filename=foo.pdf")])
      @?= Headers [("Content-Disposition", "attachment; foo=bar")]
  ]