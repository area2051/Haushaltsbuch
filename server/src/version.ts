import { readFileSync } from 'node:fs'

// src/ (tsx) and dist/ (image) both sit one level below the directory holding package.json.
const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')) as { version: string }

export const APP_VERSION: string = pkg.version
