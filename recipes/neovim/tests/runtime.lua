local prefix = assert(vim.env.PREFIX)
assert(vim.fn.has('nvim-0.12') == 1)
assert(jit and jit.status())
require('jit.opt').start('hotloop=1')
local function compute(fail)
  local sum = 0
  for i = 1, 10000 do
    sum = sum + i
    if fail and i == 9999 then
      error('devkit-jit-error')
    end
  end
  return sum
end
assert(compute(false) == 50005000)
local ok, message = pcall(compute, true)
assert(not ok and message:find('devkit-jit-error', 1, true))
assert(require('jit.util').traceinfo(1))
assert(vim.env.VIMRUNTIME == prefix .. '/lib/devkit/share/nvim/runtime')
assert(vim.fn.filereadable(vim.env.VIMRUNTIME .. '/doc/help.txt') == 1)
assert(require('vim.lsp'))
assert(require('vim.treesitter'))
assert(require('lpeg').match(require('lpeg').P('test'), 'test') == 5)
assert(vim.uv.version() >= 0x013400)

local examples = {
  c = 'int main(void) { return 0; }',
  lua = 'local answer = 42',
  vim = 'let answer = 42',
  vimdoc = '*devkit* Help text',
  query = '(identifier) @variable',
  markdown = '# Devkit\n\nText',
  markdown_inline = '**Devkit**',
}
for language, source in pairs(examples) do
  local parser = vim.treesitter.get_string_parser(source, language)
  assert(parser:parse()[1], language)
end
vim.cmd('edit edited.txt')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'devkit-neovim' })
vim.cmd('write')
vim.cmd('help help')
assert(vim.bo.buftype == 'help')
vim.cmd('qa!')
