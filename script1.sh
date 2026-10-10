#!/bin/bash
# Авторы: Ковалева Ульяна, Васильева Дарья, Смирнова Виктория

QUOTA_STR="50M"         # Задаём лимит папки
THRESHOLD_PCT=80        # Критический порог заполнения N%
MAX_M_FILES=5           # Сколько старых файлов M архивируем
BACKUP_DIR="/backup"    # Папка для хранения бэкапов

# Проверяем входящие аргументы

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "Ошибка: Укажите путь к папке логов!"
    echo "Использование: $0 <путь_к_папке>"
    exit 1
fi

TARGET_DIR="$1"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Ошибка: Целевая папка '$TARGET_DIR' не существует."
    exit 1
fi

# Создаем папку для бэкапов, если её нет
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
fi

# Доп. функции

# Конвертирует "50M" в байты для точных расчетов
parse_to_bytes() {
    local raw="$1"
    if [[ "$raw" =~ ^([0-9]+)M$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1024 * 1024))
    elif [[ "$raw" =~ ^([0-9]+)G$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1024 * 1024 * 1024))
    elif [[ "$raw" =~ ^([0-9]+)K$ ]]; then
        echo $((${BASH_REMATCH[1]} * 1024))
    else
        echo "$raw"
    fi
}

# Считает размер всех файлов в папке в байтах
get_folder_bytes() {
    du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

# Основная логика

MAX_SIZE_BYTES=$(parse_to_bytes "$QUOTA_STR")
CURRENT_SIZE_BYTES=$(get_folder_bytes "$TARGET_DIR")

# Расчет процента заполнения от максимального размера папки
CURRENT_PCT=$(( CURRENT_SIZE_BYTES * 100 / MAX_SIZE_BYTES ))

echo "=== Мониторинг папки: $TARGET_DIR ==="
echo "Установленный лимит папки: $QUOTA_STR"
echo "Текущий размер файлов:     $((CURRENT_SIZE_BYTES / 1024 / 1024)) МБ (${CURRENT_PCT}%)"
echo "Критический порог:         ${THRESHOLD_PCT}%"

# Проверка превышения порога
if [ "$CURRENT_PCT" -gt "$THRESHOLD_PCT" ]; then
    echo "Внимание! Порог в ${THRESHOLD_PCT}% превышен."
    echo "Запускается архивация $MAX_M_FILES самых старых файлов..."
    
    # Создаем изолированный временный файл для списка
    TMP_LIST=$(mktemp)
    
    # Фильтруем только файлы, сортируем по времени, берем M штук
    find "$TARGET_DIR" -maxdepth 1 -type f -printf "%T@ %p\n" 2>/dev/null \
        | sort -n \
        | head -n "$MAX_M_FILES" \
        | awk '{print $2}' > "$TMP_LIST"

    # Если нашли файлы для очистки — пакуем их
    if [ -s "$TMP_LIST" ]; then
        STAMP=$(date +%Y%m%d_%H%M%S)
        ARCHIVE_PATH="$BACKUP_DIR/log_backup_${STAMP}.tar.gz"
        
        echo "Файлы, выбранные для бэкапа:"
        cat "$TMP_LIST" | sed 's/^/  /'

        # Архивируем файлы из списка
        tar -czf "$ARCHIVE_PATH" -T "$TMP_LIST" 2>/dev/null

        # Если файл архива физически создался — безопасно удаляем оригиналы
        if [ -f "$ARCHIVE_PATH" ]; then
            echo "Архив успешно создан: $ARCHIVE_PATH"
            while IFS= read -r file; do
                rm -f "$file"
            done < "$TMP_LIST"
            echo "Оригинальные файлы удалены."
        else
            echo "Ошибка: не удалось создать архив!"
            rm -f "$TMP_LIST"
            exit 1
        fi
    else
        echo "Файлы для архивации не найдены (папка пуста)."
    fi
    
    rm -f "$TMP_LIST"
    
    # Пересчитываем и выводим измененный размер в %
    NEW_SIZE_BYTES=$(get_folder_bytes "$TARGET_DIR")
    NEW_PCT=$(( NEW_SIZE_BYTES * 100 / MAX_SIZE_BYTES ))
    echo "Новая занятость папки после очистки: $((NEW_SIZE_BYTES / 1024 / 1024)) МБ (${NEW_PCT}%)"
else
    echo "Объем папки в норме. Очистка не требуется."
fi

echo "=== Мониторинг завершен ==="
