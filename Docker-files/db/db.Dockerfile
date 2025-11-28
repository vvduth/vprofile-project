FROM mysql:8.0.33
LABEL "Project"="duke-database"
LABEL "author"="duke"

# get this from application properties file
ENV MYSQL_PASSWORD="dukepassword"
ENV MYSQL_DATABASE="accounts"

# copy the database backup file to the docker entrypoint init db folder
# all this are in the docs, all .sql files in this folder will be executed during container startup
ADD db_backup.sql docker-entrypoint-initdb.d/db_backup.sql