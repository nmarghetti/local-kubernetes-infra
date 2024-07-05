#! /bin/sh

CONTEXT_PATH="${CONTEXT_PATH#/}" # Remove leading slash
CONTEXT_PATH="${CONTEXT_PATH%/}" # Remove trailing slash
CONTEXT_PATH="/$CONTEXT_PATH"
if [ ! "${CONTEXT_PATH}" = "/" ]; then
  echo "Moving /usr/share/nginx/html/* to /usr/share/nginx/html${CONTEXT_PATH}/"
  mv "/usr/share/nginx/html" "/usr/share/nginx${CONTEXT_PATH}"
  mkdir "/usr/share/nginx/html"
  mv "/usr/share/nginx${CONTEXT_PATH}" "/usr/share/nginx/html/"
fi
