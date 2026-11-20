export type DefaultCategory = {
  name: string
  icon: string
  color: string
  kind: 'income' | 'expense'
  /** Subcategories: inherit color and kind, sortOrder = index within the parent. */
  children?: ReadonlyArray<{ name: string; icon: string }>
}

export const DEFAULT_CATEGORIES: ReadonlyArray<DefaultCategory> = [
  { name: 'Lebensmittel', icon: 'cart', color: '#4CAF50', kind: 'expense',
    children: [
      { name: 'Supermarkt', icon: 'cart' },
      { name: 'Bäckerei', icon: 'basket' },
      { name: 'Getränke', icon: 'cup.and.saucer' },
    ],
  },
  { name: 'Wohnen', icon: 'house', color: '#795548', kind: 'expense',
    children: [
      { name: 'Miete/Kredit', icon: 'house' },
      { name: 'Nebenkosten', icon: 'building.columns' },
      { name: 'Strom', icon: 'bolt' },
      { name: 'Gas', icon: 'flame' },
      { name: 'Wasser', icon: 'drop' },
      { name: 'Grundsteuer', icon: 'building.columns' },
      { name: 'Internet & Telefon', icon: 'wifi' },
      { name: 'Einrichtung', icon: 'house' },
      { name: 'Reparaturen', icon: 'wrench.and.screwdriver' },
    ],
  },
  { name: 'Mobilität', icon: 'car', color: '#2196F3', kind: 'expense',
    children: [
      { name: 'Tanken/Laden', icon: 'fuelpump' },
      { name: 'Werkstatt', icon: 'wrench.and.screwdriver' },
      { name: 'Versicherung & Steuer', icon: 'creditcard' },
      { name: 'ÖPNV', icon: 'bus' },
      { name: 'Parken', icon: 'car' },
    ],
  },
  { name: 'Freizeit', icon: 'gamecontroller', color: '#9C27B0', kind: 'expense',
    children: [
      { name: 'Restaurant & Café', icon: 'fork.knife' },
      { name: 'Ausflüge', icon: 'bicycle' },
      { name: 'Hobbys', icon: 'gamecontroller' },
      { name: 'Urlaub', icon: 'airplane' },
      { name: 'Kultur & Events', icon: 'film' },
    ],
  },
  { name: 'Gesundheit', icon: 'cross.case', color: '#F44336', kind: 'expense',
    children: [
      { name: 'Apotheke', icon: 'pills' },
      { name: 'Arzt & Zahnarzt', icon: 'cross.case' },
      { name: 'Brille', icon: 'heart' },
    ],
  },
  { name: 'Kleidung', icon: 'tshirt', color: '#E91E63', kind: 'expense',
    children: [
      { name: 'Bekleidung', icon: 'tshirt' },
      { name: 'Schuhe', icon: 'tshirt' },
    ],
  },
  { name: 'Abos', icon: 'repeat', color: '#FF9800', kind: 'expense',
    children: [
      { name: 'Streaming', icon: 'film' },
      { name: 'Musik', icon: 'music.note' },
      { name: 'Zeitungen & Apps', icon: 'book' },
      { name: 'Mitgliedschaften', icon: 'person.2' },
    ],
  },
  { name: 'Sonstiges', icon: 'ellipsis.circle', color: '#607D8B', kind: 'expense',
    children: [
      { name: 'Geschenke', icon: 'gift' },
      { name: 'Drogerie & Haushalt', icon: 'basket' },
      { name: 'Spenden', icon: 'heart' },
      { name: 'Gebühren', icon: 'eurosign' },
    ],
  },
  { name: 'Gehalt', icon: 'banknote', color: '#009688', kind: 'income' },
  { name: 'Sonstige Einnahmen', icon: 'plus.circle', color: '#8BC34A', kind: 'income',
    children: [
      { name: 'Erstattungen', icon: 'eurosign' },
      { name: 'Zinsen', icon: 'chart.line.uptrend.xyaxis' },
      { name: 'Verkäufe', icon: 'banknote' },
    ],
  },
]
