# Pinned inputs. Changing anything here changes what attendees boot, so treat
# edits as reviewed changes and re-run `make image test` afterwards.
#
# To move to a newer base image: pick a dated directory (never "latest") from
#   https://cloud.debian.org/images/cloud/$(DEBIAN_RELEASE)/
# and copy the debian-$(DEBIAN_VERSION)-generic-<arch>-<serial>.qcow2 lines
# from its SHA512SUMS file.

DEBIAN_VERSION := 13
DEBIAN_RELEASE := trixie
BASE_SERIAL    := 20261001-2618

BASE_SHA512_amd64 := 6f0f93335bdef4ccf523c4317cc663ea52ca23b862667785f3d6d186ab4674a937385ccff0c55996b4b2e4c19e440cdf211e2a75ffa2f6548037ab43950c841d
BASE_SHA512_arm64 := 001e742c14a69f3f506c1663b271b4aeed7fa766f7471a13d49ee22d338b8a637b5206a75bf994435af7b26ce3794a255dcf22e312b0d4b8d7b7f96076fe925f
