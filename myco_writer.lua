local pandoc = require 'pandoc'

----------------
-- Mycomarkup --  syntax: https://mycorrhiza.wiki/help/en/mycomarkup
----------------

Writer = pandoc.scaffolding.Writer

------------
-- Blocks --  source: https://hackage.haskell.org/package/pandoc-types-1.23.1/docs/Text-Pandoc-Definition.html#t:Block
------------

local escape = function(text)
    -- Escape special characters: \, *, _, #, `, |, ~, and +
    return text:gsub("([\\*_#`|~+])", "\\%1")
end

Writer.Block.Plain = function(plain) return { Writer.Inlines(plain.content) } end

Writer.Block.Para = function(para) return { Writer.Inlines(para.content), pandoc.layout.cr } end

Writer.Block.LineBlock = function(lineBlock)
    local lines = {}
    for _, line in ipairs(lineBlock.content) do
        lines[#lines + 1] = Writer.Inlines(line)
    end
    return lines
end

Writer.Block.CodeBlock = function(codeBlock)
    local fenceBase = "```"
    local language = ""
    if #codeBlock.classes >= 1 then
        language = codeBlock.classes[1]
    end
    local fence = fenceBase .. language
    local indent = " "

    local lines = {}
    for line in codeBlock.text:gmatch("([^\n]*)\n?") do
        table.insert(lines, indent .. line)
    end
    local codeText = table.concat(lines, "\n")
    return { fence, pandoc.layout.cr, codeText, pandoc.layout.cr, fence }
end

Writer.Block.RawBlock = function(rawBlock) return { rawBlock.text } end

Writer.Block.BlockQuote = function(blockQuote)
    local blocks = Writer.Blocks(blockQuote.content)
    local content = (type(blocks) == "table") and table.concat(blocks, "\n") or tostring(blocks)
    local lines = {}

    -- Process each line, even if it is empty.
    for line in content:gmatch("(.-)\n") do
        -- Check if it is a obsidian flavored markdown callout
        local replaced = line:gsub("^%[!(.-)%]", function(match)
            return "//**__" .. match:sub(1,1):upper() .. match:sub(2) .. "__**//:"
        end)
        table.insert(lines, "> " .. replaced)
    end

    -- Check the last line if content does not end with a newline.
    if content:sub(-1) ~= "\n" then
        local lastLine = content:match("([^\n]+)$") or ""
        lastLine = lastLine:gsub("^%[!(.-)%]", function(match)
            return "//" .. match:sub(1,1):upper() .. match:sub(2) .. "//"
        end)
        table.insert(lines, "> " .. lastLine)
    end

    return table.concat(lines, "\n") .. pandoc.layout.cr
end

Writer.Block.OrderedList = function(orderedList)
    local ret = {}
    ret[#ret + 1] = pandoc.layout.cr

    for _, v in ipairs(orderedList.content) do
        ret[#ret + 1] = [[*. ]]
        ret[#ret + 1] = Writer.Blocks(v)
        ret[#ret + 1] = pandoc.layout.cr
    end

    return ret
end

Writer.Block.BulletList = function(bulletList)
    local ret = {}
    ret[#ret + 1] = pandoc.layout.cr

    for _, item in ipairs(bulletList.content) do
        -- Check if this is a task item
        local isTask = false
        local marker = "* "

        -- Examine the first block to check for task markers
        if #item > 0 and item[1].t == "Plain" and item[1].content and #item[1].content > 0 then
            local firstInline = item[1].content[1]

            if firstInline.t == "Str" then
                if firstInline.text == "☒" then
                    isTask = true
                    -- Task is completed
                    marker = "*v "
                elseif firstInline.text == "☐" then
                    isTask = true
                    -- Task is not completed
                    marker = "*x "
                end
            end
        end

        ret[#ret + 1] = marker

        if isTask then
            -- Create a modified copy without the task marker
            local modifiedItem = { table.unpack(item) }

            -- Remove checked/unchecked marker
            table.remove(modifiedItem[1].content, 1)
            -- Remove space
            table.remove(modifiedItem[1].content, 1)

            ret[#ret + 1] = Writer.Blocks(modifiedItem)
        else
            ret[#ret + 1] = Writer.Blocks(item)
        end

        ret[#ret + 1] = pandoc.layout.cr
    end

    return ret
end

-- Definition lists are not implemented

Writer.Block.Header = function(header)
    -- Limit the header level to 4
    local marker = string.rep("=", math.min(header.level, 4))

    return {
        marker,
        pandoc.layout.space,
        Writer.Inlines(header.content),
        pandoc.layout.blankline
    }
end

Writer.Block.HorizontalRule = function(_) return [[----]] end

local function process_cell(cell)
    local result = {}
    if cell.content then
        for _, blk in ipairs(cell.content) do
            local out = Writer.Blocks({ blk })
            local content = (type(out) == "table") and table.concat(out, " ") or tostring(out)
            local string = pandoc.utils.stringify(content)
            table.insert(result, string)
        end
    end
    return table.concat(result, " ")
end

local function process_row(row, isHeader)
    local cells = {}
    for _, cell in ipairs(row.cells) do
        local cellContent = process_cell(cell)
        if isHeader then
            table.insert(cells, "! " .. cellContent)
        else
            table.insert(cells, "| " .. cellContent)
        end
    end
    return table.concat(cells, " ")
end

Writer.Block.Table = function(tbl)
    local ret = {}
    ret[#ret + 1] = "table {"

    -- Process all header rows
    if tbl.head and tbl.head.rows and #tbl.head.rows > 0 then
        for _, row in ipairs(tbl.head.rows) do
            ret[#ret + 1] = process_row(row, true)
        end
    end

    -- Process body rows
    if tbl.bodies and #tbl.bodies > 0 then
        for _, body in ipairs(tbl.bodies) do
            for _, row in ipairs(body.body) do
                ret[#ret + 1] = process_row(row, false)
            end
        end
    end

    ret[#ret + 1] = "}"
    return table.concat(ret, "\n")
end

Writer.Block.Figure = function(figure) return { Writer.Blocks(figure.content) } end

-- Div is not implemented

-------------
-- Inlines --  source: https://hackage.haskell.org/package/pandoc-types-1.23.1/docs/Text-Pandoc-Definition.html#t:Inline
-------------

Writer.Inline.Str = function(str) return escape(str.text) end

Writer.Inline.Emph = function(str) return { [[//]], Writer.Inlines(str.content), [[//]] } end

Writer.Inline.Underline = function(str) return { [[__]], Writer.Inlines(str.content), [[__]] } end

Writer.Inline.Strong = function(str) return { [[**]], Writer.Inlines(str.content), [[**]] } end

Writer.Inline.Strikeout = function(str) return { [[~~]], Writer.Inlines(str.content), [[~~]] } end

Writer.Inline.Superscript = function(str) return { [[^^]], Writer.Inlines(str.content), [[^^]] } end

Writer.Inline.Subscript = function(str) return { [[,,]], Writer.Inlines(str.content), [[,,]] } end

-- Small caps are not implemented

-- Quoted text is not implemented

-- Cite is not implemented

Writer.Inline.Code = function(code) return { [[`]], code.text, [[`]] } end

Writer.Inline.Space = pandoc.layout.space

Writer.Inline.SoftBreak = function(_) return pandoc.layout.space end

Writer.Inline.LineBreak = pandoc.layout.cr

-- Math is not implemented

Writer.Inline.RawInline = function(str) return str.text end

Writer.Inline.Link = function(link)
    local text = Writer.Inlines(link.content)
    local target = link.target

    if pandoc.utils.stringify(link.content) == target then
        return { "[[", target, "]]" }
    else
        return { "[[", target, " | ", text, "]]" }
    end
end

Writer.Inline.Image = function(image)
    local alt = ""
    if image.title and image.title ~= "" then
        alt = " { " .. image.title .. " }"
    elseif image.content and #image.content > 0 then
        alt = " { " .. pandoc.utils.stringify(image.content) .. " }"
    end

    return { "img { ", image.src, alt, " }" }
end

-- Note is rendered as superscript
-- since mycomarkup does not support notes
Writer.Inline.Note = function(note) return { [[^^]], Writer.Blocks(note.content), [[^^]] } end

-- Span is not implemented
