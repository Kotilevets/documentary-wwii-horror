# Формат архивных JSON

Каждый файл `*.json` в этой папке — массив записей. Его загружает
`src/archive/archive_db.gd` (автозагрузка `ArchiveDB`), показывает
`src/ui/archive_ui.gd`.

```json
[
  {
    "id": "act1_kommandantur_order",
    "act": 1,
    "type": "order",
    "date": "1941-…",
    "title":   { "ru": "…", "de": "…" },
    "text_status": "pending",
    "text":    { "ru": "…", "de": "…" },
    "archive_note": { "ru": "…" },
    "related": ["ref_jurisdiction_decree_1941"],
    "sources": [ { "title": "…", "url": "https://…" } ]
  }
]
```

- Два вида записей:
  - найденный в игре документ (`type`: `order`, `notice`, `summons`, `soldbuch`, `letter`, `ausweis`, `passierschein`, `leaflet`…) — на него ссылается `ItemData.document_id`;
  - справка (`type: "reference"`) — показывается во вкладке «Архивная справка» у документов, которые перечисляют её в `related`. Справку, которую не перечисляет ни один документ, игрок не увидит: тест `_test_archive` этого не пропустит.
- `text` — только подлинный текст документа, дословно, с архивным шифром в `sources`. Пока текст не внесён — `"text_status": "pending"`, и окно осмотра честно пишет, что текста ещё нет.
- `archive_note` — пояснение своими словами, без цитат длиннее одной фразы.
- `sources` — ссылки из `docs/HISTORICAL_ARCHIVE.md`. Пустой массив → предупреждение `[НЕ ПОДТВЕРЖДЕНО]` при загрузке. У книги без ссылки `url` пустой: окно показывает её название простым текстом, а название должно стоять в `docs/HISTORICAL_ARCHIVE.md`.
- Новый язык — новый ключ в `title`, `text`, `archive_note`; язык берётся из локали игры, запасной — `ru`.
