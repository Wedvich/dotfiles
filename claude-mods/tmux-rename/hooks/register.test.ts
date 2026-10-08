import { describe, expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { windowName } from './register'

function stubEngine(on: On, pane: string | undefined): string[][] {
  const runs: string[][] = []
  on('command.run', () => ({ text: 'renamed' }))
  on('env.get', (_$, e, next) => (e.name === 'TMUX_PANE' ? { value: pane } : next(e)))
  on('process.run', (_$, e) => {
    runs.push([...e.argv])
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return runs
}

async function rename($: Engine, args: string): Promise<void> {
  await $.command.run({
    command: 'rename',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
}

describe('windowName', () => {
  test('drops a trailing machine tag', () => {
    expect(windowName('bla-bla (wsl-box)')).toBe('bla-bla')
    expect(windowName('  bla-bla  ')).toBe('bla-bla')
    expect(windowName('fix (urgent) thing')).toBe('fix (urgent) thing')
  })
})

describe('/rename', () => {
  test('renames the pane\'s own window to the bare slug', async ($, on) => {
    const runs = stubEngine(on, '%7')
    await rename($, 'bla-bla (wsl-box)')
    expect(runs).toEqual([['tmux', 'rename-window', '-t', '%7', 'bla-bla']])
  })

  test('leaves tmux alone outside tmux', async ($, on) => {
    const runs = stubEngine(on, undefined)
    await rename($, 'bla-bla (wsl-box)')
    expect(runs).toEqual([])
  })

  test('leaves tmux alone on a bare /rename', async ($, on) => {
    const runs = stubEngine(on, '%7')
    await rename($, '')
    expect(runs).toEqual([])
  })
})
