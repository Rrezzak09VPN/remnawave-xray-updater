# Назначение

Данный инструмент предназначен для перевода Remnawave Node на pre-release версии Xray-core, в которых исправлена проблема с отображением пользователей Hysteria2.

В стабильных версиях Xray-core существует баг:
пользователи, подключённые через Hysteria2 inbound, могут не отображаться как “online” в панели Remnawave, несмотря на активное подключение и передачу трафика.

Этот updater автоматически устанавливает и переключает Node на pre-release сборки Xray-core, где данная проблема устранена, без необходимости ручной замены бинарника.



# ⚠️ Remnawave Xray Safe Updater

> **Дисклеймер:** Все действия производятся на **ваш страх и риск**. Автор не несёт ответственности за возможные проблемы с сервером. Перед запуском скрипта **настоятельно рекомендуется сделать бэкап**.

## 📦 Бэкап перед обновлением

```bash
# Создать копию docker-compose.yml и всего проекта
cp -r "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' \
  "$(docker ps -q --filter name=remnanode | head -n1)")" ~/remnawave-backup-$(date +%Y%m%d-%H%M%S)
```

Также рекомендуется сделать дамп базы данных, если используете PostgreSQL/MySQL в том же compose-проекте.

---

## 🚀 Одна команда

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rrezzak09VPN/remnawave-xray-updater/main/remnawave-xray-updater.sh)
```

С указанием конкретной версии Xray:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rrezzak09VPN/remnawave-xray-updater/main/remnawave-xray-updater.sh) -- 26.6.1
```

## 🔧 Как это работает

1. Находит запущенный контейнер `remnanode` по лейблу или имени
2. Определяет архитектуру (amd64 / arm64)
3. Скачивает указанную (или последнюю стабильную) версию Xray-core с GitHub
4. Проверяет целостность скачанного бинарника
5. Устанавливает бинарник в `custom-xray/xray` рядом с `docker-compose.yml`
6. Создаёт `docker-compose.override.yml` с монтированием кастомного Xray
7. Перезапускает **только** сервис Remnawave (NGINX, БД и другие сервисы не трогает)
8. Выполняет health check (12 проверок по 5 секунд) — контейнер должен быть **running** с **0 рестартов**

## 📋 Требования

- `docker` и `docker compose` (версия plugin)
- `curl`, `wget`, `unzip` — присутствуют в большинстве дистрибутивов
- Контейнер Remnawave Node должен быть запущен

## ⚙️ Параметры

| Аргумент | По умолчанию | Описание |
|----------|-------------|----------|
| `VERSION` | `26.6.1` | Версия Xray-core (без префикса v) |

## ↩️ Rollback

Скрипт выводит команду отката в конце. По умолчанию:

```bash
rm -f docker-compose.override.yml && docker compose up -d --force-recreate remnanode
```

## 🛡️ Безопасность

- Скрипт **не перезаписывает** существующий `docker-compose.override.yml` — если файл уже есть, он выдаёт предупреждение и завершается
- Все ошибки обрабатываются через `set -Eeuo pipefail` с явным trap
- Перед перезапуском проверяется версия скачанного бинарника
- После перезапуска — 60-секундный health check

## 📄 Лицензия

MIT

## ❤️ Community

Сделано для сикретнова чатика камунити Remnawave
