# AutoDHCP

Este script permite automatizar la inserción de reservas en un archivo de configuración DHCP (ISC DHCP Server).

## Uso

```bash
./autoDHCP.sh [--dry-run] <archivo_csv> <archivo_conf>
```

### Opciones

- `--dry-run`: Simula la ejecución sin modificar archivos ni reiniciar servicios

### Formato CSV esperado (separado por ';')

```csv
Nombre;MAC;Ámbito
Servidor-Web;AA:BB:CC:DD:EE:FF;Server
```

## Ejemplos

```bash
# Simular ejecución
./autoDHCP.sh --dry-run reservas.csv dhcpd.conf

# Ejecutar
./autoDHCP.sh reservas.csv dhcpd.conf
```