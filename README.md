# ZOLB - ZFS On-Line Backup

Скрипт для настройки и автомтического создания снимков файловых систем ZFS с ротацией.

Установка: 
```
sh -c '[ -f ./zolb.sh ] && STATUS="updated" || STATUS="installed"; fetch -o release.zip -q "https://github.com/Datahider/zolb/archive/refs/tags/0.0.6.zip" && unzip -q release.zip && cp $(find zolb-0.0.6 -mindepth 1 -maxdepth 1 -type f -name "zolb.sh") ./zolb.sh && chmod +x ./zolb.sh && rm -rf zolb-0.0.6 release.zip && echo "zolb.sh $STATUS for release 0.0.6."'
```
