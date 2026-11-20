-- One-off: add the default subcategories under untouched default categories.
-- A parent matches by exact name and kind (top-level, not deleted) and must have no active children yet;
-- a subcategory is skipped when an active category of that kind already has the name (case-insensitive).
-- Idempotent: a second run finds the parents with children and inserts nothing.
INSERT INTO "categories" ("name", "icon", "color", "kind", "sort_order", "parent_id")
SELECT v.name, v.icon, p.color, p.kind, v.ord, p.id
FROM (VALUES
    ('Lebensmittel', 'expense'::kind, 'Supermarkt', 'cart', 0),
    ('Lebensmittel', 'expense'::kind, 'Bäckerei', 'basket', 1),
    ('Lebensmittel', 'expense'::kind, 'Getränke', 'cup.and.saucer', 2),
    ('Wohnen', 'expense'::kind, 'Miete/Kredit', 'house', 0),
    ('Wohnen', 'expense'::kind, 'Nebenkosten', 'building.columns', 1),
    ('Wohnen', 'expense'::kind, 'Strom', 'bolt', 2),
    ('Wohnen', 'expense'::kind, 'Gas', 'flame', 3),
    ('Wohnen', 'expense'::kind, 'Wasser', 'drop', 4),
    ('Wohnen', 'expense'::kind, 'Grundsteuer', 'building.columns', 5),
    ('Wohnen', 'expense'::kind, 'Internet & Telefon', 'wifi', 6),
    ('Wohnen', 'expense'::kind, 'Einrichtung', 'house', 7),
    ('Wohnen', 'expense'::kind, 'Reparaturen', 'wrench.and.screwdriver', 8),
    ('Mobilität', 'expense'::kind, 'Tanken/Laden', 'fuelpump', 0),
    ('Mobilität', 'expense'::kind, 'Werkstatt', 'wrench.and.screwdriver', 1),
    ('Mobilität', 'expense'::kind, 'Versicherung & Steuer', 'creditcard', 2),
    ('Mobilität', 'expense'::kind, 'ÖPNV', 'bus', 3),
    ('Mobilität', 'expense'::kind, 'Parken', 'car', 4),
    ('Freizeit', 'expense'::kind, 'Restaurant & Café', 'fork.knife', 0),
    ('Freizeit', 'expense'::kind, 'Ausflüge', 'bicycle', 1),
    ('Freizeit', 'expense'::kind, 'Hobbys', 'gamecontroller', 2),
    ('Freizeit', 'expense'::kind, 'Urlaub', 'airplane', 3),
    ('Freizeit', 'expense'::kind, 'Kultur & Events', 'film', 4),
    ('Gesundheit', 'expense'::kind, 'Apotheke', 'pills', 0),
    ('Gesundheit', 'expense'::kind, 'Arzt & Zahnarzt', 'cross.case', 1),
    ('Gesundheit', 'expense'::kind, 'Brille', 'heart', 2),
    ('Kleidung', 'expense'::kind, 'Bekleidung', 'tshirt', 0),
    ('Kleidung', 'expense'::kind, 'Schuhe', 'tshirt', 1),
    ('Abos', 'expense'::kind, 'Streaming', 'film', 0),
    ('Abos', 'expense'::kind, 'Musik', 'music.note', 1),
    ('Abos', 'expense'::kind, 'Zeitungen & Apps', 'book', 2),
    ('Abos', 'expense'::kind, 'Mitgliedschaften', 'person.2', 3),
    ('Sonstiges', 'expense'::kind, 'Geschenke', 'gift', 0),
    ('Sonstiges', 'expense'::kind, 'Drogerie & Haushalt', 'basket', 1),
    ('Sonstiges', 'expense'::kind, 'Spenden', 'heart', 2),
    ('Sonstiges', 'expense'::kind, 'Gebühren', 'eurosign', 3),
    ('Sonstige Einnahmen', 'income'::kind, 'Erstattungen', 'eurosign', 0),
    ('Sonstige Einnahmen', 'income'::kind, 'Zinsen', 'chart.line.uptrend.xyaxis', 1),
    ('Sonstige Einnahmen', 'income'::kind, 'Verkäufe', 'banknote', 2)
) AS v(parent_name, kind, name, icon, ord)
JOIN "categories" p
  ON p.name = v.parent_name AND p.kind = v.kind AND p.parent_id IS NULL AND NOT p.deleted
WHERE NOT EXISTS (
  SELECT 1 FROM "categories" c WHERE c.parent_id = p.id AND NOT c.deleted
)
AND NOT EXISTS (
  SELECT 1 FROM "categories" c
  WHERE c.kind = v.kind AND NOT c.deleted AND lower(c.name) = lower(v.name)
);
