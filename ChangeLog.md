1.5.2
=====

  * Fixed `CryptoError_KeySizeInvalid` in `Web.ZeroBin.SJCL.encode`
    by using `Crypto.Cipher.AES.AES128` instead of `Crypto.Cipher.AES.AES256`


1.5.1
=====

  * Added ChangeLog
  * zerobin command supports reading stdin:
    `zerobin -f /etc/fstab` can be done as
    `cat /etc/fstab | zerobin -f -` or `zerobin -f < /etc/fstab`

