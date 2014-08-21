Follow the comments in conf.yaml.sample and create a conf.yaml file, remember to
 setup /etc/fstab, samba according to your needs.
The script can be called from cron daemon like this:
```
@daily /usr/bin/ruby1.9.1 /path/to/script/nilfs2.rb --collect
@reboot /usr/bin/ruby1.9.1 /path/to/script/nilfs2.rb --bootstrap
```
