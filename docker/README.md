# Minetest + Mineysocket server in docker

## Environment variables

All values in the minetest.conf can be changed with environment variables.

Add "MT_" in front of variable and write the variable name in upper case.

Example:

    mg_name -> MT_MG_NAME
    water_level -> MT_WATER_LEVEL

If there is a dot in the name, replace them with double underscore:

    secure.trusted_mods -> MT_SECURE__TRUSTED_MODS

Use MT_APPEND to add lines to 'minetest.conf'. Use semicolons instead of linebreaks for multiple lines.

Default values:
    
    MT_NAME=Miney
    MT_DEFAULT_PASSWORD=""
    MT_SECURE__TRUSTED_MODS=mineysocket
    MT_APPEND="mineysocket.host_ip = *;"
