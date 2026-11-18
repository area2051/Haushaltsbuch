const REJECTIONS: Record<string, string> = {
  category_in_use: 'Kategorie wird noch verwendet.',
  unknown_user: 'Person existiert nicht mehr.',
  foreign_key_violation: 'Verweis auf nicht vorhandene Daten.',
  unique_violation: 'Eintrag existiert bereits.',
  invalid_value: 'Ungültiger Wert.',
}

/** Server rejection reasons (`rejected[].reason`) for display; raw reasons are never shown. */
export const rejectionText = (reason?: string): string =>
  (reason && Object.hasOwn(REJECTIONS, reason) && REJECTIONS[reason]) || 'Vom Server abgelehnt.'

const API_ERRORS: Record<string, string> = {
  invalid_credentials: 'Benutzername oder Passwort ist falsch.',
  too_many_attempts: 'Zu viele Versuche. Bitte eine Minute warten.',
  username_taken: 'Benutzername ist bereits vergeben.',
  last_admin: 'Der letzte Admin kann nicht entfernt oder herabgestuft werden.',
  cannot_delete_self: 'Du kannst dich nicht selbst entfernen.',
  wrong_password: 'Das aktuelle Passwort ist falsch.',
  setup_already_done: 'Der Server ist bereits eingerichtet.',
  forbidden: 'Dafür fehlen dir die Rechte.',
  user_not_found: 'Mitglied nicht gefunden.',
  validation_failed: 'Eingabe ungültig.',
  unreachable: 'Keine Verbindung zum Server.',
}

/** API error codes (`error.code`) for display. */
export const apiErrorText = (code?: string): string =>
  (code && Object.hasOwn(API_ERRORS, code) && API_ERRORS[code]) || 'Etwas ist schiefgelaufen. Bitte erneut versuchen.'
