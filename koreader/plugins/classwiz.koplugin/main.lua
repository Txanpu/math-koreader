local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")

local ClassWiz = WidgetContainer:extend({
    name = "classwiz",
})

local function new_seq(parent, role)
    return {
        kind = "seq",
        items = {},
        parent = parent,
        role = role,
    }
end

local function gcd(a, b)
    a, b = math.abs(math.floor(a)), math.abs(math.floor(b))
    while b ~= 0 do
        a, b = b, a % b
    end
    return a == 0 and 1 or a
end

function ClassWiz:init()
    self.ans = 0
    self.mem = 0
    self.shift = false
    self.display_mode = "frac" -- "frac", "dec", "mixed", "fact", "caja"
    self.last_val = nil
    self.last_num = nil
    self.last_den = nil
    self.error_msg = nil
    self.window = nil

    self:_resetExpr()
    self.ui.menu:registerToMainMenu(self)
end

function ClassWiz:addToMainMenu(menu_items)
    menu_items.classwiz = {
        text = _("Calculadora ClassWiz 2D"),
        sorting_hint = "tools",
        callback = function()
            self:show()
        end,
    }
end

function ClassWiz:_resetExpr()
    self.root_seq = new_seq(nil, "root")
    self.cursor_seq = self.root_seq
    self.cursor_pos = 0
    self.last_val = nil
    self.last_num = nil
    self.last_den = nil
    self.error_msg = nil
    self.display_mode = "frac"
end

function ClassWiz:_makeText(text, font_size)
    return TextWidget:new({
        text = text,
        face = Font:getFace("cfont", font_size or 18),
    })
end

function ClassWiz:_makeSolidBar(w, h, color)
    return FrameContainer:new({
        background = color or Blitbuffer.COLOR_BLACK,
        bordersize = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new({
            dimen = Geom:new({
                w = math.max(1, math.floor(w)),
                h = math.max(1, math.floor(h)),
            }),
            self:_makeText("", 2),
        }),
    })
end

function ClassWiz:_makeSpacer(w, h)
    return CenterContainer:new({
        dimen = Geom:new({
            w = math.max(1, math.floor(w)),
            h = math.max(1, math.floor(h)),
        }),
        self:_makeText("", 2),
    })
end

function ClassWiz:_makeButton(text, callback, width, height, bordersize)
    return Button:new({
        text = text,
        callback = function()
            callback()
        end,
        width = width,
        height = height,
        bordersize = bordersize or 2,
        radius = 0,
        margin = 1,
        padding = 1,
    })
end

function ClassWiz:_closeWindow(is_exiting)
    if self.window then
        UIManager:close(self.window)
        self.window = nil
        if is_exiting then
            UIManager:setDirty("all", "ui")
        end
    end
end

-- Inserta un token de texto/operador en la posición actual del cursor
function ClassWiz:_insertToken(text, eval_str, is_num_part)
    if self.last_val ~= nil and self.cursor_seq == self.root_seq then
        if is_num_part then
            self:_resetExpr()
        else
            local ans_val = self.last_val
            self:_resetExpr()
            self.ans = ans_val
            table.insert(self.root_seq.items, {
                kind = "tok",
                text = "Ans",
                eval = tostring(self.ans),
                is_num = true,
            })
            self.cursor_pos = 1
        end
    end

    self.last_val = nil
    self.error_msg = nil
    self.cursor_pos = self.cursor_pos + 1
    table.insert(self.cursor_seq.items, self.cursor_pos, {
        kind = "tok",
        text = text,
        eval = eval_str or text,
        is_num = is_num_part or false,
    })
    self.shift = false
    self:show()
end

-- Inserta una fracción 2D (si hay dígitos justo antes del cursor, los sube al numerador)
function ClassWiz:_insertFraction()
    self.last_val = nil
    self.error_msg = nil

    local frac_node = {
        kind = "frac",
        parent_seq = self.cursor_seq,
    }
    frac_node.num = new_seq(frac_node, "num")
    frac_node.den = new_seq(frac_node, "den")

    local captured = {}
    while self.cursor_pos > 0 do
        local prev = self.cursor_seq.items[self.cursor_pos]
        if prev and prev.kind == "tok" and prev.is_num then
            table.insert(captured, 1, prev)
            table.remove(self.cursor_seq.items, self.cursor_pos)
            self.cursor_pos = self.cursor_pos - 1
        else
            break
        end
    end

    self.cursor_pos = self.cursor_pos + 1
    table.insert(self.cursor_seq.items, self.cursor_pos, frac_node)

    if #captured > 0 then
        frac_node.num.items = captured
        self.cursor_seq = frac_node.den
        self.cursor_pos = 0
    else
        self.cursor_seq = frac_node.num
        self.cursor_pos = 0
    end

    self.shift = false
    self:show()
end

function ClassWiz:_insertSqrt()
    self.last_val = nil
    self.error_msg = nil

    local sqrt_node = {
        kind = "sqrt",
        parent_seq = self.cursor_seq,
    }
    sqrt_node.rad = new_seq(sqrt_node, "rad")

    self.cursor_pos = self.cursor_pos + 1
    table.insert(self.cursor_seq.items, self.cursor_pos, sqrt_node)
    self.cursor_seq = sqrt_node.rad
    self.cursor_pos = 0
    self.shift = false
    self:show()
end

function ClassWiz:_insertPow(prefill_tok)
    self.last_val = nil
    self.error_msg = nil

    local pow_node = {
        kind = "pow",
        parent_seq = self.cursor_seq,
    }
    pow_node.exp = new_seq(pow_node, "exp")

    self.cursor_pos = self.cursor_pos + 1
    table.insert(self.cursor_seq.items, self.cursor_pos, pow_node)

    if prefill_tok then
        table.insert(pow_node.exp.items, {
            kind = "tok",
            text = prefill_tok,
            eval = prefill_tok,
            is_num = true,
        })
    else
        self.cursor_seq = pow_node.exp
        self.cursor_pos = 0
    end

    self.shift = false
    self:show()
end

function ClassWiz:_findNodeIndex(seq, target_node)
    for i, item in ipairs(seq.items) do
        if item == target_node then
            return i
        end
    end
    return 0
end

-- Navegación por cursores 2D (Izquierda, Derecha, Arriba, Abajo)
function ClassWiz:_moveLeft()
    if self.cursor_pos > 0 then
        local item = self.cursor_seq.items[self.cursor_pos]
        if item.kind == "frac" then
            self.cursor_seq = item.den
            self.cursor_pos = #item.den.items
        elseif item.kind == "sqrt" then
            self.cursor_seq = item.rad
            self.cursor_pos = #item.rad.items
        elseif item.kind == "pow" then
            self.cursor_seq = item.exp
            self.cursor_pos = #item.exp.items
        else
            self.cursor_pos = self.cursor_pos - 1
        end
    elseif self.cursor_seq.parent then
        local p = self.cursor_seq.parent
        if self.cursor_seq.role == "den" then
            self.cursor_seq = p.num
            self.cursor_pos = #p.num.items
        else
            local idx = self:_findNodeIndex(p.parent_seq, p)
            self.cursor_seq = p.parent_seq
            self.cursor_pos = math.max(0, idx - 1)
        end
    end
    self:show()
end

function ClassWiz:_moveRight()
    if self.cursor_pos < #self.cursor_seq.items then
        local item = self.cursor_seq.items[self.cursor_pos + 1]
        if item.kind == "frac" then
            self.cursor_seq = item.num
            self.cursor_pos = 0
        elseif item.kind == "sqrt" then
            self.cursor_seq = item.rad
            self.cursor_pos = 0
        elseif item.kind == "pow" then
            self.cursor_seq = item.exp
            self.cursor_pos = 0
        else
            self.cursor_pos = self.cursor_pos + 1
        end
    elseif self.cursor_seq.parent then
        local p = self.cursor_seq.parent
        if self.cursor_seq.role == "num" then
            self.cursor_seq = p.den
            self.cursor_pos = 0
        else
            local idx = self:_findNodeIndex(p.parent_seq, p)
            self.cursor_seq = p.parent_seq
            self.cursor_pos = idx
        end
    end
    self:show()
end

function ClassWiz:_moveUp()
    local cur = self.cursor_seq
    while cur do
        if cur.role == "den" and cur.parent then
            self.cursor_seq = cur.parent.num
            self.cursor_pos = math.min(self.cursor_pos, #self.cursor_seq.items)
            self:show()
            return
        end
        cur = cur.parent and cur.parent.parent_seq or nil
    end

    local adj = self.cursor_seq.items[self.cursor_pos] or self.cursor_seq.items[self.cursor_pos + 1]
    if adj and adj.kind == "frac" then
        self.cursor_seq = adj.num
        self.cursor_pos = #adj.num.items
        self:show()
    elseif adj and adj.kind == "pow" then
        self.cursor_seq = adj.exp
        self.cursor_pos = #adj.exp.items
        self:show()
    end
end

function ClassWiz:_moveDown()
    local cur = self.cursor_seq
    while cur do
        if cur.role == "num" and cur.parent then
            self.cursor_seq = cur.parent.den
            self.cursor_pos = math.min(self.cursor_pos, #self.cursor_seq.items)
            self:show()
            return
        elseif cur.role == "exp" and cur.parent then
            local p = cur.parent
            local idx = self:_findNodeIndex(p.parent_seq, p)
            self.cursor_seq = p.parent_seq
            self.cursor_pos = idx
            self:show()
            return
        end
        cur = cur.parent and cur.parent.parent_seq or nil
    end

    local adj = self.cursor_seq.items[self.cursor_pos] or self.cursor_seq.items[self.cursor_pos + 1]
    if adj and adj.kind == "frac" then
        self.cursor_seq = adj.den
        self.cursor_pos = 0
        self:show()
    end
end

function ClassWiz:_deleteBack()
    self.last_val = nil
    self.error_msg = nil
    if self.cursor_pos > 0 then
        table.remove(self.cursor_seq.items, self.cursor_pos)
        self.cursor_pos = self.cursor_pos - 1
    elseif self.cursor_seq.parent then
        local p = self.cursor_seq.parent
        local parent_seq = p.parent_seq
        local idx = self:_findNodeIndex(parent_seq, p)
        if idx > 0 then
            table.remove(parent_seq.items, idx)
            self.cursor_seq = parent_seq
            self.cursor_pos = idx - 1
        end
    end
    self:show()
end

-- Convierte un árbol 2D en expresión matemática evaluable en Lua
function ClassWiz:_seqToLua(seq)
    if #seq.items == 0 then
        return "0"
    end
    local parts = {}
    for i, item in ipairs(seq.items) do
        local prev = seq.items[i - 1]
        if prev then
            local prev_is_val = (prev.kind == "frac" or prev.kind == "sqrt" or prev.kind == "pow")
                or (prev.kind == "tok" and (prev.is_num or prev.text == "))")
            local cur_needs_mul = (item.kind == "frac" or item.kind == "sqrt")
                or (item.kind == "tok" and (item.text == "(" or item.text == "π" or item.text == "e"
                    or string.find(item.text, "^a?s?e?n?c?o?s?t?a?n?l?o?g?l?n?%(")))
            if prev_is_val and cur_needs_mul then
                table.insert(parts, "*")
            end
        end

        if item.kind == "tok" then
            table.insert(parts, item.eval)
        elseif item.kind == "frac" then
            local n_str = self:_seqToLua(item.num)
            local d_str = self:_seqToLua(item.den)
            table.insert(parts, "((" .. n_str .. ")/(" .. d_str .. "))")
        elseif item.kind == "sqrt" then
            local r_str = self:_seqToLua(item.rad)
            table.insert(parts, "SQRT(" .. r_str .. ")")
        elseif item.kind == "pow" then
            local e_str = self:_seqToLua(item.exp)
            table.insert(parts, "^(" .. e_str .. ")")
        end
    end
    return table.concat(parts, "")
end

function ClassWiz:_evalLuaString(expr_str)
    local open_p = 0
    for _ in string.gmatch(expr_str, "%(") do open_p = open_p + 1 end
    for _ in string.gmatch(expr_str, "%)") do open_p = open_p - 1 end
    if open_p > 0 then
        expr_str = expr_str .. string.rep(")", open_p)
    end

    local env = {
        math = math,
        ANS = self.ans,
        PI = math.pi,
        E = math.exp(1),
        SQRT = math.sqrt,
        SIND = function(x) return math.sin(math.rad(x)) end,
        COSD = function(x) return math.cos(math.rad(x)) end,
        TAND = function(x) return math.tan(math.rad(x)) end,
        ASIND = function(x) return math.deg(math.asin(x)) end,
        ACOSD = function(x) return math.deg(math.acos(x)) end,
        ATAND = function(x) return math.deg(math.atan(x)) end,
        LOG10 = function(x) return math.log(x) / math.log(10) end,
        LN = math.log,
    }

    local chunk, err = load("return " .. expr_str, "calc", "t", env)
    if not chunk then
        return nil
    end
    local ok, res = pcall(chunk)
    if not ok or type(res) ~= "number" or res ~= res or math.abs(res) == math.huge then
        return nil
    end
    return res
end

-- Convierte un decimal en fracción exacta p/q mediante fracciones continuas
function ClassWiz:_toExactFraction(val)
    local sign = val < 0 and -1 or 1
    local x = math.abs(val)
    if math.abs(x - math.floor(x + 0.5)) < 1e-10 then
        return sign * math.floor(x + 0.5), 1
    end

    local h1, h2 = 1, 0
    local k1, k2 = 0, 1
    local b = x
    for _ = 1, 18 do
        local a = math.floor(b)
        local h = a * h1 + h2
        local k = a * k1 + k2
        if k > 99999 then
            break
        end
        h2, h1 = h1, h
        k2, k1 = k1, k
        if math.abs(x - (h1 / k1)) < 1e-9 then
            local g = gcd(h1, k1)
            return sign * math.floor(h1 / g), math.floor(k1 / g)
        end
        local rem = b - a
        if rem < 1e-11 then
            break
        end
        b = 1 / rem
    end
    return nil, nil
end

-- Extrae dividendo y divisor si la operación principal es una fracción o división
function ClassWiz:_extractDivisionPair()
    if #self.root_seq.items == 1 and self.root_seq.items[1].kind == "frac" then
        local f = self.root_seq.items[1]
        local n_val = self:_evalLuaString(self:_seqToLua(f.num))
        local d_val = self:_evalLuaString(self:_seqToLua(f.den))
        if n_val and d_val and d_val ~= 0 then
            return math.floor(math.abs(n_val) + 0.5), math.floor(math.abs(d_val) + 0.5)
        end
    end

    for i, item in ipairs(self.root_seq.items) do
        if item.kind == "tok" and item.text == "÷" then
            local left_seq = new_seq(nil, "tmp")
            local right_seq = new_seq(nil, "tmp")
            for j = 1, i - 1 do table.insert(left_seq.items, self.root_seq.items[j]) end
            for j = i + 1, #self.root_seq.items do table.insert(right_seq.items, self.root_seq.items[j]) end
            local n_val = self:_evalLuaString(self:_seqToLua(left_seq))
            local d_val = self:_evalLuaString(self:_seqToLua(right_seq))
            if n_val and d_val and d_val ~= 0 then
                return math.floor(math.abs(n_val) + 0.5), math.floor(math.abs(d_val) + 0.5)
            end
        end
    end

    if self.last_num and self.last_den and self.last_den > 1 then
        return math.abs(self.last_num), math.abs(self.last_den)
    end
    return nil, nil
end

function ClassWiz:_calculate(target_mode)
    if #self.root_seq.items == 0 then
        return
    end
    local expr_str = self:_seqToLua(self.root_seq)
    local res = self:_evalLuaString(expr_str)
    if not res then
        self.error_msg = _("Math ERROR")
        self.last_val = nil
    else
        self.error_msg = nil
        self.last_val = res
        self.ans = res
        local p, q = self:_toExactFraction(res)
        self.last_num = p
        self.last_den = q
        self.display_mode = target_mode or "frac"
    end
    self.shift = false
    self:show()
end

function ClassWiz:_toggleSD()
    if not self.last_val then
        self:_calculate("dec")
        return
    end
    if self.display_mode == "frac" then
        self.display_mode = "dec"
    elseif self.display_mode == "dec" and self.last_num and self.last_den and self.last_den > 1
        and math.abs(self.last_num) > self.last_den then
        self.display_mode = "mixed"
    else
        self.display_mode = "frac"
    end
    self:show()
end

-- Renderizador recursivo 2D de expresiones matemáticas
function ClassWiz:_renderSeq(seq, depth)
    local font_sz = (depth == 0) and 22 or ((depth == 1) and 17 or 14)

    if #seq.items == 0 then
        local is_active = (self.cursor_seq == seq)
        return FrameContainer:new({
            background = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            bordersize = is_active and 2 or 1,
            padding = 2,
            margin = 2,
            self:_makeText(is_active and "▪" or "▢", font_sz - 2),
        })
    end

    local row = HorizontalGroup:new({ align = "center" })

    for i = 0, #seq.items do
        if self.cursor_seq == seq and self.cursor_pos == i and self.last_val == nil then
            table.insert(row, self:_makeSolidBar(2, font_sz + 4, Blitbuffer.COLOR_BLACK))
        end

        if i >= 1 then
            local item = seq.items[i]
            if item.kind == "tok" then
                table.insert(row, self:_makeText(item.text, font_sz))
            elseif item.kind == "frac" then
                local num_w = self:_renderSeq(item.num, depth + 1)
                local den_w = self:_renderSeq(item.den, depth + 1)
                local n_sz = num_w:getSize()
                local d_sz = den_w:getSize()
                local bar_w = math.max(n_sz.w, d_sz.w, 18) + 8

                local frac_widget = FrameContainer:new({
                    background = Blitbuffer.COLOR_WHITE,
                    bordersize = 0,
                    padding = 1,
                    margin = 2,
                    VerticalGroup:new({
                        align = "center",
                        num_w,
                        self:_makeSpacer(bar_w, 1),
                        self:_makeSolidBar(bar_w, 2, Blitbuffer.COLOR_BLACK),
                        self:_makeSpacer(bar_w, 1),
                        den_w,
                    }),
                })
                table.insert(row, frac_widget)
            elseif item.kind == "sqrt" then
                local rad_w = self:_renderSeq(item.rad, depth + 1)
                local r_sz = rad_w:getSize()
                local top_bar = self:_makeSolidBar(r_sz.w + 6, 2, Blitbuffer.COLOR_BLACK)
                local left_wall = self:_makeSolidBar(2, r_sz.h + 4, Blitbuffer.COLOR_BLACK)

                local roofed = VerticalGroup:new({
                    align = "center",
                    top_bar,
                    FrameContainer:new({
                        background = Blitbuffer.COLOR_WHITE,
                        bordersize = 0,
                        padding = 2,
                        rad_w,
                    }),
                })

                table.insert(row, HorizontalGroup:new({
                    align = "center",
                    self:_makeText("√", font_sz + 2),
                    left_wall,
                    roofed,
                }))
            elseif item.kind == "pow" then
                local exp_w = self:_renderSeq(item.exp, depth + 1)
                local e_sz = exp_w:getSize()
                local raised = VerticalGroup:new({
                    align = "center",
                    exp_w,
                    self:_makeSpacer(e_sz.w, math.floor(font_sz * 0.55)),
                })
                table.insert(row, raised)
            end
        end
    end

    return row
end

-- Construye el gráfico de Zatiketa en Caja de Papel (Dividendo | Divisor)
function ClassWiz:_buildPaperDivisionWidget(D, d)
    local q = math.floor(D / d)
    local rem_final = D % d
    local D_str = tostring(D)

    local left_lines = VerticalGroup:new({ align = "left" })
    table.insert(left_lines, self:_makeText(" " .. D_str, 18))

    local cur = 0
    local started = false
    local steps_shown = 0
    for i = 1, #D_str do
        local digit = tonumber(string.sub(D_str, i, i))
        cur = cur * 10 + digit
        if cur >= d or started or i == #D_str then
            started = true
            local rem = cur % d
            local next_char = (i < #D_str) and string.sub(D_str, i + 1, i + 1) or ""
            local line_txt = tostring(rem) .. next_char
            local pad_len = math.max(0, i - #tostring(rem))
            local padded = " " .. string.rep(" ", pad_len * 2) .. line_txt
            if steps_shown < 4 then
                table.insert(left_lines, self:_makeText(padded, 16))
                steps_shown = steps_shown + 1
            end
            cur = rem
        end
    end

    local div_text = self:_makeText(" " .. tostring(d) .. " ", 18)
    local div_sz = div_text:getSize()
    local quo_text = self:_makeText(" " .. tostring(q) .. " ", 18)
    local quo_sz = quo_text:getSize()
    local box_w = math.max(div_sz.w, quo_sz.w, 36) + 8

    -- Caja gráfica |___ con el divisor arriba y el cociente debajo
    local divisor_with_wall = HorizontalGroup:new({
        align = "center",
        self:_makeSolidBar(2, div_sz.h + 4, Blitbuffer.COLOR_BLACK),
        div_text,
    })

    local right_box = VerticalGroup:new({
        align = "left",
        divisor_with_wall,
        self:_makeSolidBar(box_w, 2, Blitbuffer.COLOR_BLACK),
        self:_makeSpacer(box_w, 2),
        quo_text,
        self:_makeText(string.format(_("Resto (Hondarra): %d"), rem_final), 14),
    })

    return HorizontalGroup:new({
        align = "center",
        left_lines,
        self:_makeSpacer(12, 10),
        right_box,
    })
end

-- Construye el widget de descomposición en factores primos 2D (FACT)
function ClassWiz:_buildPrimeFactorsWidget(n)
    local num = math.floor(math.abs(n) + 0.5)
    if num < 2 or num > 999999999 then
        return self:_makeText(tostring(n), 22)
    end

    local factors = {}
    local d = 2
    local temp = num
    while d * d <= temp do
        if temp % d == 0 then
            local count = 0
            while temp % d == 0 do
                count = count + 1
                temp = math.floor(temp / d)
            end
            table.insert(factors, { p = d, e = count })
        end
        d = (d == 2) and 3 or (d + 2)
    end
    if temp > 1 then
        table.insert(factors, { p = temp, e = 1 })
    end

    local row = HorizontalGroup:new({ align = "center" })
    for i, f in ipairs(factors) do
        if i > 1 then
            table.insert(row, self:_makeText(" × ", 20))
        end
        table.insert(row, self:_makeText(tostring(f.p), 22))
        if f.e > 1 then
            local exp_t = self:_makeText(tostring(f.e), 14)
            local esz = exp_t:getSize()
            table.insert(row, VerticalGroup:new({
                align = "center",
                exp_t,
                self:_makeSpacer(esz.w, 10),
            }))
        end
    end
    return row
end

-- Construye el widget de resultado en la esquina inferior derecha del LCD
function ClassWiz:_buildResultWidget()
    if self.error_msg then
        return self:_makeText(self.error_msg, 22)
    end
    if self.last_val == nil then
        return self:_makeText("", 18)
    end

    if self.display_mode == "caja" then
        local D, d = self:_extractDivisionPair()
        if D and d and d > 0 then
            return self:_buildPaperDivisionWidget(D, d)
        end
    elseif self.display_mode == "fact" then
        return self:_buildPrimeFactorsWidget(self.last_val)
    elseif self.display_mode == "mixed" and self.last_num and self.last_den and self.last_den > 1 then
        local sign_str = self.last_num < 0 and "-" or ""
        local abs_n = math.abs(self.last_num)
        local whole = math.floor(abs_n / self.last_den)
        local rem = abs_n % self.last_den
        if whole > 0 and rem > 0 then
            local n_w = self:_makeText(tostring(rem), 17)
            local d_w = self:_makeText(tostring(self.last_den), 17)
            local bw = math.max(n_w:getSize().w, d_w:getSize().w, 16) + 6
            return HorizontalGroup:new({
                align = "center",
                self:_makeText(sign_str .. tostring(whole) .. " ", 22),
                VerticalGroup:new({
                    align = "center",
                    n_w,
                    self:_makeSolidBar(bw, 2, Blitbuffer.COLOR_BLACK),
                    d_w,
                }),
            })
        end
    elseif self.display_mode == "frac" and self.last_num and self.last_den and self.last_den > 1 then
        local sign_str = self.last_num < 0 and "− " or ""
        local n_w = self:_makeText(tostring(math.abs(self.last_num)), 19)
        local d_w = self:_makeText(tostring(self.last_den), 19)
        local bw = math.max(n_w:getSize().w, d_w:getSize().w, 18) + 8
        return HorizontalGroup:new({
            align = "center",
            self:_makeText(sign_str, 22),
            VerticalGroup:new({
                align = "center",
                n_w,
                self:_makeSpacer(bw, 1),
                self:_makeSolidBar(bw, 2, Blitbuffer.COLOR_BLACK),
                self:_makeSpacer(bw, 1),
                d_w,
            }),
        })
    end

    local formatted = string.format("%.10g", self.last_val)
    return self:_makeText(formatted, 24)
end

function ClassWiz:show()
    self:_closeWindow(false)

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local panel_w = screen_w - 20

    local lcd_h = math.floor(screen_h * 0.25)
    local nav_h = math.max(38, math.floor(screen_h * 0.06))
    local sci_h = math.max(38, math.floor(screen_h * 0.058))
    local num_h = math.max(46, math.floor(screen_h * 0.078))

    local w_6 = math.floor((panel_w - 24) / 6)
    local w_5 = math.floor((panel_w - 20) / 5)

    -- 1. Cabecera estilo Casio fx-570SP X II Iberia ClassWiz
    local header_row = HorizontalGroup:new({
        align = "center",
        self:_makeText(_("CASIO   fx-570SP X II Iberia   [CLASSWIZ]"), 17),
        self:_makeSpacer(16, 10),
        self:_makeButton(_("Salir"), function()
            self:_closeWindow(true)
        end, math.floor(panel_w * 0.20), math.max(34, math.floor(nav_h * 0.8)), 2),
    })

    -- 2. Pantalla LCD Gráfica 2D (tamaño fijo para que nunca mueva los botones)
    local status_str = string.format(
        "[D]  [Math ▲▼]  %s  %s",
        self.shift and "[SHIFT]" or "[Natural-V.P.A.M.]",
        self.mem ~= 0 and "[M]" or ""
    )
    local expr_widget = self:_renderSeq(self.root_seq, 0)
    local res_widget = self:_buildResultWidget()

    local lcd_content = VerticalGroup:new({
        align = "center",
        self:_makeText(status_str, 13),
        self:_makeSpacer(panel_w - 28, 2),
        expr_widget,
        self:_makeSpacer(panel_w - 28, 4),
        res_widget,
    })

    local lcd_box = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 3,
        padding = 6,
        margin = 2,
        CenterContainer:new({
            dimen = Geom:new({ w = panel_w - 20, h = lcd_h }),
            lcd_content,
        }),
    })

    -- 3. Fila de Cursores 2D (◀ ▲ ▼ ▶) + SHIFT + Zatiketa en Caja (÷R)
    local nav_row = HorizontalGroup:new({
        align = "center",
        self:_makeButton(self.shift and _("��SHIFT•") or _("SHIFT"), function()
            self.shift = not self.shift
            self:show()
        end, w_6, nav_h, self.shift and 4 or 2),
        self:_makeButton(_("◀"), function() self:_moveLeft() end, w_6, nav_h, 2),
        self:_makeButton(_("▲"), function() self:_moveUp() end, w_6, nav_h, 2),
        self:_makeButton(_("▼"), function() self:_moveDown() end, w_6, nav_h, 2),
        self:_makeButton(_("▶"), function() self:_moveRight() end, w_6, nav_h, 2),
        self:_makeButton(_("÷R Caja"), function()
            self:_calculate("caja")
        end, w_6, nav_h, 3),
    })

    -- 4. Bloque Científico (3 filas x 6 columnas idénticas a la Casio ClassWiz)
    local sci_row1 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("▢/▢"), function() self:_insertFraction() end, w_6, sci_h, 3),
        self:_makeButton(_("√▢"), function() self:_insertSqrt() end, w_6, sci_h, 2),
        self:_makeButton(self.shift and _("x³") or _("x²"), function()
            self:_insertPow(self.shift and "3" or "2")
        end, w_6, sci_h, 2),
        self:_makeButton(_("x^▢"), function() self:_insertPow(nil) end, w_6, sci_h, 2),
        self:_makeButton(_("log"), function()
            self:_insertToken("log(", "LOG10(", false)
        end, w_6, sci_h, 2),
        self:_makeButton(_("ln"), function()
            self:_insertToken("ln(", "LN(", false)
        end, w_6, sci_h, 2),
    })

    local sci_row2 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("(-)"), function()
            self:_insertToken("-", "-", true)
        end, w_6, sci_h, 2),
        self:_makeButton(_("FACT"), function()
            self:_calculate("fact")
        end, w_6, sci_h, 2),
        self:_makeButton(_("x⁻¹"), function()
            self:_insertPow("-1")
        end, w_6, sci_h, 2),
        self:_makeButton(self.shift and _("asen") or _("sen"), function()
            self:_insertToken(self.shift and "asen(" or "sen(", self.shift and "ASIND(" or "SIND(", false)
        end, w_6, sci_h, 2),
        self:_makeButton(self.shift and _("acos") or _("cos"), function()
            self:_insertToken(self.shift and "acos(" or "cos(", self.shift and "ACOSD(" or "COSD(", false)
        end, w_6, sci_h, 2),
        self:_makeButton(self.shift and _("atan") or _("tan"), function()
            self:_insertToken(self.shift and "atan(" or "tan(", self.shift and "ATAND(" or "TAND(", false)
        end, w_6, sci_h, 2),
    })

    local sci_row3 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("π"), function()
            self:_insertToken("π", "PI", true)
        end, w_6, sci_h, 2),
        self:_makeButton(_("e"), function()
            self:_insertToken("e", "E", true)
        end, w_6, sci_h, 2),
        self:_makeButton(_("("), function()
            self:_insertToken("(", "(", false)
        end, w_6, sci_h, 2),
        self:_makeButton(_(")"), function()
            self:_insertToken(")", ")", false)
        end, w_6, sci_h, 2),
        self:_makeButton(_("S⇔D"), function()
            self:_toggleSD()
        end, w_6, sci_h, 3),
        self:_makeButton(self.shift and _("M-") or _("M+"), function()
            self:_calculate(self.display_mode)
            if self.last_val then
                self.mem = self.mem + (self.shift and -self.last_val or self.last_val)
                self:show()
            end
        end, w_6, sci_h, 2),
    })

    -- 5. Teclado Numérico Principal (4 filas x 5 columnas igual que la Casio)
    local num_row1 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("7"), function() self:_insertToken("7", "7", true) end, w_5, num_h, 2),
        self:_makeButton(_("8"), function() self:_insertToken("8", "8", true) end, w_5, num_h, 2),
        self:_makeButton(_("9"), function() self:_insertToken("9", "9", true) end, w_5, num_h, 2),
        self:_makeButton(_("DEL"), function() self:_deleteBack() end, w_5, num_h, 3),
        self:_makeButton(_("AC"), function()
            self:_resetExpr()
            self:show()
        end, w_5, num_h, 3),
    })

    local num_row2 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("4"), function() self:_insertToken("4", "4", true) end, w_5, num_h, 2),
        self:_makeButton(_("5"), function() self:_insertToken("5", "5", true) end, w_5, num_h, 2),
        self:_makeButton(_("6"), function() self:_insertToken("6", "6", true) end, w_5, num_h, 2),
        self:_makeButton(_("×"), function() self:_insertToken("×", "*", false) end, w_5, num_h, 2),
        self:_makeButton(_("÷"), function() self:_insertToken("÷", "/", false) end, w_5, num_h, 2),
    })

    local num_row3 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("1"), function() self:_insertToken("1", "1", true) end, w_5, num_h, 2),
        self:_makeButton(_("2"), function() self:_insertToken("2", "2", true) end, w_5, num_h, 2),
        self:_makeButton(_("3"), function() self:_insertToken("3", "3", true) end, w_5, num_h, 2),
        self:_makeButton(_("+"), function() self:_insertToken("+", "+", false) end, w_5, num_h, 2),
        self:_makeButton(_("−"), function() self:_insertToken("−", "-", false) end, w_5, num_h, 2),
    })

    local num_row4 = HorizontalGroup:new({
        align = "center",
        self:_makeButton(_("0"), function() self:_insertToken("0", "0", true) end, w_5, num_h, 2),
        self:_makeButton(_("."), function() self:_insertToken(".", ".", true) end, w_5, num_h, 2),
        self:_makeButton(_("×10ˣ"), function()
            self:_insertToken("×10", "*10", false)
            self:_insertPow(nil)
        end, w_5, num_h, 2),
        self:_makeButton(_("Ans"), function()
            self:_insertToken("Ans", "ANS", true)
        end, w_5, num_h, 2),
        self:_makeButton(_("="), function()
            self:_calculate("frac")
        end, w_5, num_h, 3),
    })

    local layout = VerticalGroup:new({
        align = "center",
        header_row,
        lcd_box,
        nav_row,
        sci_row1,
        sci_row2,
        sci_row3,
        num_row1,
        num_row2,
        num_row3,
        num_row4,
    })

    self.window = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new({
            dimen = Screen:getSize(),
            layout,
        }),
    })

    UIManager:show(self.window)
    UIManager:setDirty(self.window, "ui")
    UIManager:setDirty("all", "ui")
end

return ClassWiz
