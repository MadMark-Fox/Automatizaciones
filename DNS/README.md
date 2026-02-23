# AutoDNS

Script interactivo para gestionar registros en un archivo de zona DNS (BIND9)

## Características

- Añadir registros A, AAAA, CNAME, MX, NS y TXT
- Eliminar registros
- Actualizar el serial del SOA automáticamente
- Validar formatos de direcciones IP y nombres de host
- Colores para mejor legibilidad

## Uso

```bash
chmod +x autoDNS.sh
./autoDNS.sh
```

## Configuración

El script utiliza el archivo de zona ubicado en la misma carpeta que el script.

## Licencia

MIT