#!/usr/bin/env bash

MINETEST_CONF="/var/lib/minetest/.minetest/minetest.conf"

# loop over vars and replace in minetest.conf
for var in $(compgen -e); do
  if [[ $var == "MT_"* ]]; then
    var_lower="$(echo "${var//__/\.}"| tr '[:upper:]' '[:lower:]')"  # __ to . and to lower case
    var_value=$(printenv "$var")
    sed -i "s/^# ${var_lower#*mt_} =.*/${var_lower#*mt_} = $var_value/" $MINETEST_CONF
    sed -i "s/^${var_lower#*mt_} =.*/${var_lower#*mt_} = $var_value/" $MINETEST_CONF
  fi
done

echo "$MT_APPEND" | tr ";" "\n" >> $MINETEST_CONF

if [ "$MTDEFAULT_PASSWORD" == "" ]
then
  echo "The admin username is '$MT_NAME' and the default password for all users is empty."
else
  echo "The admin username is '$MT_NAME' and the default password for all users is '$MT_DEFAULT_PASSWORD'."
fi

exec /usr/local/bin/minetestserver --config /var/lib/minetest/.minetest/minetest.conf --gameid minetest --worldname minetest