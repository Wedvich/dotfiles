import type { Register } from 'claude-code'

// Claude names sessions "slug (machine-tag)"; the window keeps the bare slug.
export function windowName(sessionName: string): string {
  return sessionName.trim().replace(/\s*\([^()]*\)$/, '')
}

export const register: Register = on => {
  on('command.run', { command: 'rename' }, async ($, e, next) => {
    const result = await next(e)
    // bare /rename lets Claude pick the name, which this hook can't see
    const name = windowName(e.args)
    if (name === '') return result

    const pane = await $.env.get('TMUX_PANE')
    if (pane === undefined || pane === '') return result

    // -t pane id: rename Claude's own window, not whichever has focus
    const ran = await $.process.run(['tmux', 'rename-window', '-t', pane, name])
    if (ran.exitCode !== 0) $.ui.toast(`tmux rename-window failed: ${ran.stderr.trim()}`)
    return result
  })
    // fail open: a tmux hiccup must never cost the rename itself
    .catch(($, e, next) => next(e))
}
