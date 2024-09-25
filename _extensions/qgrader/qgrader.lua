traverse = "typewise"

local keys = {
  output = "qgrader-output",
  replacement = "qgrader-replace",
  answer = "qgrader-answer",
}
local options = pandoc.MetaMap({
  [keys.output] = "student",
  [keys.replacement] = "#| replace: (.*)",
  [keys.answer] = "# Your answer here",
})

function codeblock_replacer_student(line)
  local indent = line:match("( *)[a-zA-Z]+")
  local replacement = line:match(options[keys.replacement])
  if replacement then
    return table.concat({indent, replacement}, "")
  end
  return nil
end

function codeblock_replacer_grader(line)
  return line:gsub(options[keys.replacement], "")
end

local codeblock_replacer = {
  student = codeblock_replacer_student,
  grader  = codeblock_replacer_grader ,
}

---@param cb pandoc.CodeBlock
function render_codeblock(cb)
  local grader = cb.attr.attributes.grader
  if grader == nil then
    return cb
  end

  local code  = cb.text .. "\n"

  if options[keys.output] == "student" and not code:gmatch(options[keys.replacement]) then
    cb.text = options[keys.answer]
    return cb
  end

  local lines = pandoc.List()

  for line in code:gmatch("([^\r\n]*)[\r\n]") do
    line = codeblock_replacer[options[keys.output]](line) or line
    lines:insert(line)
  end
  
  cb.text = table.concat(lines, "\n")

  return cb
end

---@param div pandoc.Div
function render_div(div)
  -- quarto.log.output(div)
  local grader = div.attr.attributes.grader
  if grader == nil then
    return div
  end

  if options[keys.output] == "student" then
    local frq = pandoc.CodeBlock("# Your answer here", pandoc.Attr())
    local blocks = {}
    for _, block in pairs(div.content) do
      if block.t == "CodeBlock" then
        blocks[#blocks+1] = block
      else
        blocks[#blocks+1] = blocks[#blocks] ~= frq and frq or nil
      end
    end
    return pandoc.Div(blocks)
  end

  return div
end

---@param callout quarto.Callout
function render_callout(callout)
  local grader = callout.attr.attributes.grader

  if grader == nil then
    return callout
  end

  if options[keys.output] == "student" then
    return pandoc.Div(callout.content)
  end
  
  callout.icon = false
  callout.appearance = "minimal"
  callout.title = pandoc.Inlines{
    pandoc.Str("Grader:"),
    pandoc.Space(),
    pandoc.Strong{pandoc.Str(grader)},
  }

  return callout
end

function get_options(meta)
  if (meta[keys.output] == nil) then
    meta[keys.output] = options[keys.output]
  end
  if meta[keys.output] == "student" then
    meta.execute = { eval = false, cache = false }
  end
  options[keys.output] = tostring(meta[keys.output])

  if (meta[keys.replacement] == nil) then
    meta[keys.replacement] = options[keys.replacement]
  end
  options[keys.replacement] = tostring(meta[keys.replacement])

  if (meta[keys.answer] == nil) then
    meta[keys.answer] = options[keys.answer]
  end
  options[keys.answer] = tostring(meta[keys.answer])

  return meta
end

function propagate_graders(el, grader)
  if el.attr then
    el.attr.attributes["grader"] = grader
  end

  if el.content then
    for _, inner in ipairs(el.content) do
      propagate_graders(inner, grader)
    end
  end

  return el
end

---@params callout quarto.Callout
function attach_graders(el)
  local grader = el.attr.attributes["grader"]
  if grader ~= nil then
    local content = el.content
    if content.attr == nil then
      local attr = pandoc.Attr("", {}, { grader = grader })
      content = pandoc.Div(content, attr)
    end
    content.attr.attributes["grader"] = grader
    el.content = propagate_graders(content, grader)
  end
  return el
end

-- Make sure that we run in 4 passes so the `Metadata` is collected first!
return {
  { Meta = get_options, },
  { Callout = attach_graders },
  { Div = render_div, CodeBlock = render_codeblock },
  { Callout = render_callout, },
}