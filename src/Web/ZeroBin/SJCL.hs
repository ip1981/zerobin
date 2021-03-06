{-|
Encryption compatible with <https://crypto.stanford.edu/sjcl/ SJCL>

 >>> import Web.ZeroBin.SJCL
 >>> import Data.ByteString.Char8
 >>> encrypt "secret-word" (pack "hello")
Content {iv = "VxyuJRVtKJqhG2iR/sPjAQ", salt = "AhnDuP1CkTCBlQTHgw", ct = "cqr7/pMRXrcROmcgwA"}
-}
{-# LANGUAGE DeriveGeneric #-}

module Web.ZeroBin.SJCL
  ( Content(..)
  , encrypt
  ) where

import Crypto.Cipher.AES (AES128)
import Crypto.Cipher.Types
       (blockSize, cipherInit, ctrCombine, ecbEncrypt, ivAdd, makeIV)
import Crypto.Error (throwCryptoErrorIO)
import Crypto.Hash.Algorithms (SHA256(..))
import Crypto.KDF.PBKDF2 (prfHMAC)
import qualified Crypto.KDF.PBKDF2 as PBKDF2
import Crypto.Number.Serialize (i2ospOf_)
import Crypto.Random.Entropy (getEntropy)
import qualified Data.Aeson as JSON
import qualified Data.ByteArray as BA
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import Data.Maybe (fromJust)
import Data.Word (Word8)
import GHC.Generics (Generic)
import Web.ZeroBin.Utils (toWeb)

-- | Encrypted content. Each field is a 'toWeb'-encoded byte-string
data Content = Content
  { iv :: String -- ^ random initialization vector (IV)
  , salt :: String -- ^ random salt
  , ct :: String -- ^ encrypted data
  } deriving (Generic, Show)

-- FIXME: http://stackoverflow.com/questions/33045350/unexpected-haskell-aeson-warning-no-explicit-implementation-for-tojson
instance JSON.ToJSON Content where
  toJSON = JSON.genericToJSON JSON.defaultOptions

makeCipher :: ByteString -> IO AES128
makeCipher = throwCryptoErrorIO . cipherInit

-- https://github.com/bitwiseshiftleft/sjcl/blob/master/core/pbkdf2.js
-- TODO: this is default, we can specify it explicitly for forward compatibility
makeKey :: ByteString -> ByteString -> ByteString
makeKey =
  PBKDF2.generate
    (prfHMAC SHA256)
    PBKDF2.Parameters {PBKDF2.iterCounts = 1000, PBKDF2.outputLength = 16}

chunks :: Int -> ByteString -> [ByteString]
chunks sz = split
  where
    split b
      | cl <= sz = [b'] -- padded
      | otherwise = b1 : split b2
      where
        cl = BS.length b
        (b1, b2) = BS.splitAt sz b
        b' = BS.take sz $ BS.append b (BS.replicate sz 0)

lengthOf :: Int -> Word8
lengthOf = ceiling . (logBase 256 :: Float -> Float) . fromIntegral

-- | <https://crypto.stanford.edu/sjcl/ SJCL>-compatible encryption function.
--   Follows <https://tools.ietf.org/html/rfc3610 RFC3610> with a 8-bytes tag.
--   Uses 16-bytes cipher key generated from the password and a random 'salt'
--   by PBKDF2-HMAC-SHA256 with 1000 iterations.
encrypt ::
     String -- ^ the password
  -> ByteString -- ^ the plain data to encrypt
  -> IO Content
encrypt password plaintext = do
  ivd <- getEntropy 16 -- XXX it is truncated to get the nonce below
  slt <- getEntropy 13 -- arbitrary length
  cipher <- makeCipher $ makeKey (C.pack password) slt
  let tlen = 8 :: Word8
      l = BS.length plaintext
      eL = max 2 (lengthOf l)
      nonce = BS.take (15 - fromIntegral eL) ivd
      b0 =
        BS.concat
          [ BS.pack [8 * ((tlen - 2) `div` 2) + (eL - 1)]
          , nonce
          , i2ospOf_ (fromIntegral eL) (fromIntegral l)
          ]
      mac =
        foldl
          (\a b -> ecbEncrypt cipher $ BA.xor a b)
          (ecbEncrypt cipher b0)
          (chunks (blockSize cipher) plaintext)
      tag = BS.take (fromIntegral tlen) mac
      a0 = BS.concat [BS.pack [eL - 1], nonce, BS.replicate (fromIntegral eL) 0]
      a1iv = ivAdd (fromJust . makeIV $ a0) 1
      ciphtext =
        BS.append
          (ctrCombine cipher a1iv plaintext)
          (BA.xor (ecbEncrypt cipher a0) tag)
  return Content {iv = toWeb ivd, salt = toWeb slt, ct = toWeb ciphtext}
