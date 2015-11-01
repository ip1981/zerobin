module ZeroBin.Utils (
  toWeb
, makePassword
) where

import Crypto.Random.Entropy (getEntropy)
import Data.ByteString (ByteString)
import Data.ByteString.Base64 (encode)
import Data.ByteString.Char8 (unpack)
import Data.Char (isAlphaNum)


toWeb :: ByteString -> String
toWeb = takeWhile (/= '=') . unpack . encode

makePassword :: Int -> IO String
makePassword n = (map (\c -> if isAlphaNum c then c else 'X')
                  . toWeb) `fmap` getEntropy n

