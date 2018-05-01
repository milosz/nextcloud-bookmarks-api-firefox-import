#!/bin/sh
# Import Firefox bookmarks to Nexcloud
# https://blog.sleeplessbeastie.eu/

# path to the sqlite3 binary
sqlite_path=$(which sqlite3)

# sqlite3 parameters (define separator character)
sqlite_params="-separator ^"

# path to the places.sqlite database
bookmarks_database=$(ls ~/.mozilla/firefox/*.default/places.sqlite)

# SQL query 
sql_query="select p.title, p.url from moz_places as p where p.hidden=0 order by last_visit_date desc limit 10"

# root element
root_element_query="select id from moz_bookmarks where rtrim(guid,'_')='menu'"
root_element="$($sqlite_path $sqlite_params "$bookmarks_database" "$root_element_query")"

# escape html
escape_html() {
  echo $* | perl -n -mHTML::Entities -e "print HTML::Entities::encode_entities_numeric(\$_,'<>&\"\'[](){}#@|%+')"
}

# process bookmarks
process_bookmarks(){
  # create folder path
  folder_id=$1
  folder_path=""
  while [ "$folder_id" != "2" ]; do
    sql_folder_query="select parent,title from moz_bookmarks where id=$folder_id and type=2 and (select count(*) from moz_bookmarks as b2 where b2.parent=moz_bookmarks.id)>0"

    sql_folder_result=$($sqlite_path $sqlite_params "$bookmarks_database" "$sql_folder_query" )
    folder_id=$(echo $sql_folder_result | awk -F^ '{print $1}')
    folder_title=$(echo $sql_folder_result | awk -F^ '{print $2}')

    if [ -z "$folder_path" ]; then
      folder_path="$folder_title"
    else
      folder_path="${folder_title}>${folder_path}"
    fi
  done
  folder_path="floccus:>${folder_path}"


  # process bookmarks
  sql_bookmarks_query="select b.title, p.url from moz_bookmarks as b left outer join moz_places as p on b.fk=p.id where b.type = 1 and p.hidden=0 and b.title not null and parent=$1"
  $sqlite_path $sqlite_params "$bookmarks_database" "$sql_bookmarks_query" | while IFS=^ read ff_title ff_url; do
    # check if url is already stored before adding it
    found_bookmark="0"
    continue_pagination="1"
    page=0
    while [ "${continue_pagination}" -eq "1" ]; do
      urls=$(curl --silent -X GET --user "${param_username}:${param_password}" \
                                  --header "Accept: application/json" \
                  "${param_nextcloud_address}/index.php/apps/bookmarks/public/rest/v2/bookmark?page=${page}&search\[\]=$(escape_html $ff_url)" | \
             jq -r '.data[].url')
      if [ -z "${urls}" ]; then
        continue_pagination="0"
      else
        for url in $urls; do
          if [ "$ff_url" == "$url" ]; then
            found_bookmark="1"
            break 
          fi
        done
      fi

      if [ "${found_bookmark}" -eq "0" ]; then
        status=$(curl --silent -X POST --user "${param_username}:${param_password}" \
                                       --data-urlencode "url=$ff_url" \
                                       --data-urlencode "title=$ff_title" \
                                       --data-urlencode "item[tags][]=$folder_path" \
                      "${param_nextcloud_address}/index.php/apps/bookmarks/public/rest/v2/bookmark" | \
                 jq -r 'select(.status != "success") | .status')
        if [ -n "${status}" ]; then
          echo "Skipped Nextcloud bookmark url \"${ff_url}\" with title \"${ff_title}\" and tag \"${folder_path}\"."
        else
          echo "Added Nextcloud bookmark url \"${ff_url}\" with title \"${ff_title}\" and tag \"${folder_path}\"."
        fi
        continue_pagination="0"
        page="0"
      else
        page=$(expr $page + 1)
      fi
    done
  done
}

# process the folders function
process_folders(){
  # execute only when there is an exactly one parameter
  if [ "$#" = 1 ]; then
    # SQL query - folders
    sql_folder_query="select id from moz_bookmarks where parent=$1 and type=2 and (select count(*) from moz_bookmarks as b2 where b2.parent=moz_bookmarks.id)>0"

    # process folders
    $sqlite_path $sqlite_params "$bookmarks_database" "$sql_folder_query" | while IFS=^ read id; do
      # process folders inside
      process_folders $id
      
      # process bookmarks in current folder
      process_bookmarks $id 
    done
  fi
}

# usage info
usage(){
  echo "Usage:"
  echo "  $0 -r nextcloud_url -u username -p passsword"
  echo ""
  echo "Parameters:"
  echo "  -r nextcloud_url   : set Nextcloud URL (required)"
  echo "  -u username        : set username (required)"
  echo "  -p password        : set password (required)"
  echo ""
}

# parse parameters
while getopts "r:u:p:" option; do
  case $option in
    "r")
      param_nextcloud_address="${OPTARG}"
      param_nextcloud_address_defined=true
      ;;
    "u")
      param_username="${OPTARG}"
      param_username_defined=true
      ;;
    "p")
      param_password="${OPTARG}"
      param_password_defined=true
      ;;
    \?|:|*)
      usage
      exit
      ;;
  esac
done

if [ "${param_nextcloud_address_defined}" = true ] && \
   [ "${param_username_defined}"          = true ] && \
   [ "${param_password_defined}"          = true ]; then

  # process folders 
  process_folders "$root_element"

  # process bookmarks for root element
  process_bookmarks "$root_element"
else
  usage
fi
