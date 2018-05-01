#!/bin/sh
# Export Firefox bookmarks 

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

# process bookmarks
process_bookmarks(){
  # SQL query - folders
  folder_id=$1
  folder_path=""
  while [ "$folder_id" != "2" ]; do
    sql_folder_query="select parent,title from moz_bookmarks where id=$folder_id and type=2 and (select count(*) from moz_bookmarks as b2 where b2.parent=moz_bookmarks.id)>0"

    sql_folder_result=$($sqlite_path $sqlite_params "$bookmarks_database" "$sql_folder_query" )
    folder_id=$(echo $sql_folder_result | awk -F^ '{print $1}')
    folder_title=$(echo $sql_folder_result | awk -F^ '{print $2}')

    # special case for empty title
    if [ -z "$folder_path" ]; then
      folder_path="floccus:>$folder_title"
    else
      folder_path="${folder_path}>${folder_title}"
    fi
  done

  # escape special characters
  folder_path=$(echo $folder_path | sed -e "s/&/\&amp;/g" -e "s/\"/\&quot;/g" -e "s/</\&lt;/g" -e "s/>/\&gt;/g")

  # SQL query - bookmarks
  sql_bookmarks_query="select b.title, p.url from moz_bookmarks as b left outer join moz_places as p on b.fk=p.id where b.type = 1 and p.hidden=0 and b.title not null and parent=$1"
  $sqlite_path $sqlite_params "$bookmarks_database" "$sql_bookmarks_query" | while IFS=^ read title url; do
    # special case for empty title
    if [ -z "$title" ]; then
      title=$url
    fi

    # escape special characters
    title=$(echo $title | sed -e "s/&/\&amp;/g" -e "s/\"/\&quot;/g" -e "s/</\&lt;/g" -e "s/>/\&gt;/g")
    url=$(echo $url | sed -e "s/&/\&amp;/g" -e "s/\"/\&quot;/g" -e "s/</\&lt;/g" -e "s/>/\&gt;/g")

    # display url, title, path
    echo "<DT><A HREF=\"${url}\" TAGS=\"${folder_path}\">${title}</A>"
  done
}

# process the folders function
process_folders(){
  # execute only when there is an axactly one parameter
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


# header
echo "<!DOCTYPE NETSCAPE-Bookmark-file-1>"
echo "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">"
echo "<!-- This is an automatically generated file."
echo "It will be read and overwritten."
echo "Do Not Edit! -->"
echo "<TITLE>Bookmarks</TITLE>"
echo "<H1>Bookmarks</H1>"
echo "<DL><p>"

# process folders 
process_folders "$root_element"

# process bookmarks for root element
process_bookmarks "$root_element"

