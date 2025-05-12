# peertube-kidui

This is a very simple WebUI for peertube that should be used only in
private and secure networks.

My purpose by using peertube is to colcect and share our video contents
within my family only. So my entire config is lightweight for that purpose.

## Installation

Lets assume you alredy have peertube installed.

```
git clone git@github.com:csjpeter/peertube-kidui.git
cd peertube-kidui
ln -s $PWD /var/www/peertube/kidui
```

Alternatively you can copy the content of the
peertube-kidui folder to your web content folder.

You can find my peertube production.yaml in this repository.

### Nginx configuration

The next step is to adjust nginx configuration of peertube.

In file /etc/nginx/sites-available/peertub, before the part commented as
```
  ##
  # Application
  ##

  location @api {
```
insert this:

```
  location /kidui {
    add_header Access-Control-Allow-Origin *;
    add_header Content-Security-Policy "
        default-src     'self' 'unsafe-inline' 'unsafe-eval' blob: data:; 
        media-src       'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        img-src         'self' 'unsafe-inline' 'unsafe-eval' blob: data:; 
        font-src        'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        worker-src      'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        script-src      'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        script-src-elem 'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        script-src-attr 'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        style-src       'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
        style-src-elem  'self' 'unsafe-inline' 'unsafe-eval' blob: data:;
     " always;
    disable_symlinks off;
    root /var/www/peertube/kidui;
    index index.html;
    try_files /index.html =404;
  }
```

You can also find my full nginx config file, which has more adjustments
for my private needs.
