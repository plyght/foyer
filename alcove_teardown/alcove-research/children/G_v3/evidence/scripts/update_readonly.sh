curl --silent --show-error --request GET \
  --header 'Accept: application/json' \
  --dump-header update_get_headers.txt \
  --output update_get_body.json \
  'https://api.tryalcove.com/updates/latest'
