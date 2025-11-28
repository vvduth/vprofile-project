FROM nginx
LABEL "Project"="duke-web"
LABEL "author"="duke"

# remoce the default nginx config file
#RUN rm -rf /etc/nginx/nginx.conf
# copy our custom nginx config file
COPY nginxduke.conf /etc/nginx/nginx.conf