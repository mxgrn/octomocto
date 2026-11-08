# nginx error page

`50x.html` is a static page that the nginx load balancer shows when it cannot
get a response from the app (502, 504). The page has no external files: the
logo and the CSS are in the HTML. Thus, it works when the app is down.

## Install

1. Copy the page to the load balancer. Use `scp`. Do not paste the content
   into an editor over SSH: the terminal can lose or change parts of it.

   ```bash
   scp rel/nginx/50x.html user@load-balancer:/tmp/50x.html
   ```

2. On the load balancer, move the page to the site folder:

   ```bash
   sudo mkdir -p /var/www/octomocto.com && sudo mv /tmp/50x.html /var/www/octomocto.com/50x.html && sudo chmod 644 /var/www/octomocto.com/50x.html
   ```

   Do not put the page in `/etc/nginx/sites-enabled/`. nginx reads all files
   in that folder as config, and an HTML file there stops nginx.

3. In the site config in `/etc/nginx/sites-enabled/`, add the `error_page`
   line and the `location = /50x.html` block to the HTTPS `server` block
   (the block with `listen 443`), after `location /`:

   ```nginx
   server {
     server_name octomocto.com;

     location / {
       include proxy_params;
       proxy_pass http://octomocto;
     }

     error_page 500 502 503 504 /50x.html;
     location = /50x.html {
       root /var/www/octomocto.com;
       internal;
     }

     listen 443 ssl; # managed by Certbot
     # ... other Certbot lines ...
   }
   ```

   - `root` is the folder that contains the page. nginx adds `/50x.html` to it.
   - `internal` prevents users from opening `/50x.html` directly.
   - Do not change the HTTP `server` block (port 80). It only sends visitors
     to HTTPS.

4. Test the config and reload nginx:

   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

## When users see the page

- The `octomocto` upstream has two app servers. When one server does not
  answer, nginx sends the request to the other one. Users see the page only
  when no app server answers.
- When Phoenix sends a 500 itself, users see the Phoenix error page, not this
  page. To show this page in that case too, add `proxy_intercept_errors on;`
  to `location /`. We do not use it.

## Test

Stop the app on all app servers (or point the upstream at a port that has
nothing on it), then open https://octomocto.com.

## Update

After you change `50x.html`, do steps 1 and 2 again. You do not need to reload
nginx.
