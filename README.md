# Script to modify Ubuntu Server 

This script was used to edit the ``installer`` user access privileges such that
one can log on via ssh with a known password.

This script was only ever tested on the ``ubuntu-22.04.3-live-server-amd64.iso`` image downloaded from [here](https://ubuntu.com/download/server).

## Preparation steps:

1) Download ``ubuntu-22.04.3-live-server-amd64.iso`` from [here](https://ubuntu.com/download/server).
2) Before you start you may need to generate a secret key with gpg with which
you can sign the modified files. See e.g. [here](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key) for instructions. Then you run ``gpg --list-secret-keys`` which will give you a bunch of entries like so:
    ```
    sec   rsa2048 2013-01-31 [SC]
      E09E68EBDF159CBBE5D3F36FB811924CF8D1CA04    # <<< this is the key to provide
    uid           [ unknown] Your Name Here <foo.bar@gmail.com>
    ssb   rsa2048 2013-01-31 [E]
    ```
    You will need to provide the key marked above when you run the script.
3) You will need to have an ssh public key file available, aka ``id_rsa.pub``.
4) You need a temporary directory where a couple of Gigs can be temporarily used


## How to run it:

Run the script like so:

```bash
chmod a+x ./modify_image.bash
./modify_image.bash -i ubuntu-22.04.3-live-server-amd64.iso -o hacked_image.iso -w /path/to/my/working/directory -k my_gpg_key -s ~/.ssh/id_rsa.pub
```
