## elemental reset

elemental reset OS

```
elemental reset [flags]
```

### Options

```
      --cosign                Enable cosign verification (requires images with signatures)
      --cosign-key string     Sets the URL of the public key to be used by cosign validation
      --directory string      Use directory as source to install from
  -d, --docker-image string   Install a specified container image
  -h, --help                  help for reset
      --no-verify             Disable mtree checksum verification (requires images manifests generated with mtree separately)
      --poweroff              Shutdown the system after install
      --reboot                Reboot the system after install
      --reset-persistent      Clear persistent partitions
      --strict                Enable strict check of hooks (They need to exit with 0)
      --tty                   Add named tty to grub
```

### Options inherited from parent commands

```
      --config-dir string   set config dir (default is /etc/elemental) (default "/etc/elemental")
      --debug               enable debug output
      --logfile string      set logfile
      --quiet               do not output to stdout
```

### SEE ALSO

* [elemental](elemental.md)	 - elemental
