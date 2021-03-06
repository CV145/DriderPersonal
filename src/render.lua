-- this module holds all the code for rendering an html fragment such as
-- that produced by the html module
local render = {}
local utils = import("utils")
local pathlib = import("pathlib")

local padding = 5
local margin = 10

local ink = Color.new(0, 0, 0)
local paper = Color.new(255, 255, 200)
local pencil = Color.new(230, 230, 180)
local red = Color.new(175, 18, 18)

local regularFont = Font.load(pathlib.nearby("gentium_regular.ttf"))
local italicFont = Font.load(pathlib.nearby("gentium_italic.ttf"))
local titleFont = italicFont

Graphics.init()

local function renderText(text, font, size, fgColor, textwidth)
	if textwidth == nil then
		textwidth = 0
	end
	local width, height, image, texture
	local magenta = Color.new(255, 0, 255)

	Font.setPixelSizes(font, size)
	width, height = Font.measureText(font, text, textwidth)
	image = Screen.createImage(width, height, magenta)
	Font.print(font, 0, 0, text, fgColor, image, 0, textwidth)
	texture = Graphics.convertFrom(image)
	Screen.freeImage(image)
	return texture
end

-- CLASS: MenuRenderer
render.MenuRenderer = {}
render.MenuRenderer.__index = render.MenuRenderer
render.MenuRenderer.size = 20
function render.MenuRenderer:new(choices)
	local obj = {}
	setmetatable(obj, render.MenuRenderer)
	obj.dirty = true
	obj.selected = 1
	obj.position = -10
	obj.images = {}
	obj.choices = {}

	obj.banner = Graphics.loadImage(pathlib.nearby("banner.png"))
	table.insert(obj.images, obj.banner)

	obj.imgDisTex = renderText("Images Disabled", italicFont, self.size, ink, paper)
	table.insert(obj.images, obj.imgDisTex)

	for _, choice in ipairs(choices) do
		local tex = renderText(choice, regularFont, self.size, ink, paper)
		table.insert(obj.choices, tex)
		table.insert(obj.images, tex)
	end
	return obj
end

function render.MenuRenderer:free()
	for _, image in ipairs(self.images) do
		Graphics.freeImage(image)
	end
end

function render.MenuRenderer:select(selected)
	self.selected = selected
	self.dirty = true
end

function render.MenuRenderer:drawChoices()
	local middle = 240 / 2
	for i, tex in ipairs(self.choices) do
		local rel_i = i - self.position
		local offset = middle - self.size / 2
		local y = rel_i * self.size + offset
		local color = paper
		if i == self.selected then
			color = red
			Graphics.fillRect(0, 320, y, y + self.size, color)
		end
		Graphics.drawImage(margin, y, tex, color)
	end
end

function render.MenuRenderer:drawImagesDisabled()
	local width = Graphics.getImageWidth(self.imgDisTex)
	local height = Graphics.getImageHeight(self.imgDisTex)
	Graphics.drawImage(400 - width, 240 - height, self.imgDisTex, paper)
end

function render.MenuRenderer:update()
	if math.abs(self.position - self.selected) > 0.1 then
		self.position = utils.lerp(self.position, self.selected, 0.1)
		self.dirty = true
	end
end

function render.MenuRenderer:draw(showImages)
	Screen.waitVblankStart()
	if not self.dirty then
		return
	end

	Graphics.initBlend(TOP_SCREEN)
	Graphics.fillRect(0, 400, 0, 240, paper)
	Graphics.drawImage(75, 32, self.banner)
	if not showImages then
		self:drawImagesDisabled()
	end
	Graphics.termBlend()

	Graphics.initBlend(BOTTOM_SCREEN)
	Graphics.fillRect(0, 320, 0, 240, paper)
	self:drawChoices()
	Graphics.termBlend()

	Graphics.flip()

	self.dirty = false
end

render.PageRenderer = {}
render.PageRenderer.__index = render.PageRenderer
render.PageRenderer.bookmark = Graphics.loadImage(pathlib.nearby("bookmark.png"))
render.PageRenderer.h1size = 32
render.PageRenderer.h2size = 28
render.PageRenderer.h3size = 24
render.PageRenderer.psize = 16
render.PageRenderer.textwidth = 320 - margin * 2
render.PageRenderer.friction = 0.95
function render.PageRenderer:new(book, showImages)
	local obj = {}
	setmetatable(obj, render.PageRenderer)
	obj.book = book
	obj.showImages = showImages
	obj.textures = {}
	obj.offset = -500
	obj.position = 0
	obj.velocity = 0
	obj.dirty = true
	obj:__compile()
	obj:__calcHeight()
	obj.pageNumTex = renderText(book.pagenum, italicFont, 32, pencil)
	table.insert(obj.textures, obj.pageNumTex)
	return obj
end

function render.PageRenderer:free()
	for i, texture in ipairs(self.textures) do
		Graphics.freeImage(texture)
	end
end

function render.PageRenderer:__compile()
	self.idata = {
		pagenum = self.book.pagenum
	}
	local html = self.book:currentPageHTML()
	table.insert(self.idata, {type = "space", height = margin})

	local function insertText(text, font, size)
		Font.setPixelSizes(font, size)
		local w, h = Font.measureText(font, text, self.textwidth)
		table.insert(
			self.idata,
			{
				type = "text",
				height = h,
				width = w,
				font = font,
				size = size,
				content = text
			}
		)
	end

	for _, item in ipairs(html) do
		if item.type == "h1" then
			insertText(item.content, titleFont, self.h1size)
		elseif item.type == "h2" then
			insertText(item.content, titleFont, self.h2size)
		elseif item.type == "h3" then
			insertText(item.content, titleFont, self.h3size)
		elseif item.type == "p" then
			for _, line in ipairs(item.content:wrap(50)) do
				insertText(line, regularFont, self.psize)
			end
		elseif item.type == "img" then
			local image, w, h = self:loadImage(item)
			local scale = self:scale(w, h)
			table.insert(
				self.idata,
				{
					type = "image",
					height = h * scale,
					width = w * scale,
					src = item.src,
					alt = item.alt,
					render = image,
					scale = scale
				}
			)
		else
			local msg = "[WARNING: Unknown tag %q]"
			insertText(msg:format(item.type), italicFont, self.psize)
		end
		table.insert(self.idata, {type = "space", height = padding})
	end

	table.insert(self.idata, {type = "space", height = padding * 3})
end

function render.PageRenderer:__calcHeight()
	self.height = 0
	for _, item in ipairs(self.idata) do
		self.height = self.height + item.height
	end
end

function render.PageRenderer:scale(width, height)
	if width > self.textwidth then
		return self.textwidth / width
	end
	return 1
end

function render.PageRenderer:loadImage(item)
	local ext = item.src:match("%.%w+$")

	local bad_ext = true
	if ext == ".jpg" or ext == ".bmp" or ext == ".png" then
		bad_ext = false
	end

	local image
	if bad_ext or not self.showImages then
		image = renderText(string.format('Image: "%s"\n%s', item.alt, item.src), italicFont, 20, pencil, self.textwidth)
	else
		local filename = self.book:imageFile(item.src)
		image = Graphics.loadImage(filename)
	end

	table.insert(self.textures, image)
	local w = Graphics.getImageWidth(image)
	local h = Graphics.getImageHeight(image)

	return image, w, h
end

function render.PageRenderer:scroll(amount)
	self.position = self.position + amount
	self.dirty = true

	local max_pos = math.max(self.height - 480, 0)
	if self.position > max_pos then
		self.position = max_pos
		self.velocity = 0
	end

	local min_pos = math.min(-240, self.height - 480)
	if self.position < min_pos then
		self.position = min_pos
		self.velocity = 0
	end
end

function render.PageRenderer:update()
	if self.offset < 0.1 then
		self.offset = utils.lerp(self.offset, 0, 0.1)
		self.dirty = true
	end

	if math.abs(self.velocity) > 0.1 then
		self:scroll(self.velocity)
	end
	self.velocity = self.velocity * self.friction
end

function render.PageRenderer:getImage(tap_x, tap_y)
	local top = self.position + 240
	local bottom = self.position + 480

	local y = 0
	for _, item in ipairs(self.idata) do
		if y + item.height < top then
			goto skip_item
		elseif bottom < y then
			break
		end

		if item.type == "image" then
			local x_hit = margin < tap_x and tap_x < margin + item.width
			local y_hit = y - top < tap_y and tap_y < y - top + item.height
			if x_hit and y_hit then
				return item.render
			end
		end

		::skip_item::
		y = y + item.height
	end
end

function render.PageRenderer:drawBookmark()
	if self.book:isCurrentBookmarked() then
		local x, h = 370, 25
		Graphics.fillRect(x, x + 16, 0, h, red)
		Graphics.drawImage(x, h, self.bookmark)
	end
end

function render.PageRenderer:drawScrollbar() --
	--[[local min_height = 6
	local screen_ratio = 240 / self.height
	local sbHeight = math.floor(480 * screen_ratio + 0.5)
	local sbTop = self.position * screen_ratio

	sbHeight = math.max(min_height, sbHeight)

	local sbBottom = sbTop + sbHeight

	sbTop = math.floor(math.max(0, math.min(240 - min_height, sbTop)))
	sbBottom = math.ceil(math.max(min_height, math.min(240, sbBottom)))

	if sbTop ~= 0 or sbBottom ~= 240 then
		Graphics.fillRect(400 - min_height, 400, sbTop, sbBottom, pencil)
	end]]
end

function render.PageRenderer:drawPageNum()
	Graphics.drawImage(margin, 0, self.pageNumTex, paper)
end

function render.PageRenderer:drawContents(left, top, bottom)
	local y = 0
	for _, item in ipairs(self.idata) do
		if y + item.height < top then
			goto skip_drawing
		elseif bottom < y then
			break
		end

		if item.type == "text" then
			if item.render == nil then
				item.render = renderText(item.content, item.font, item.size, ink, self.textwidth)
				table.insert(self.textures, item.render)
			end
			Graphics.drawImage(left, y - top, item.render, paper)
		elseif item.type == "image" then
			Graphics.drawScaleImage(left, y - top, item.render, item.scale, item.scale)
		end

		::skip_drawing::
		y = y + item.height
	end
end

function render.PageRenderer:draw()
	Screen.waitVblankStart()
	if not self.dirty then
		return
	end

	Graphics.initBlend(TOP_SCREEN)
	Graphics.fillRect(0, 400, 0, 240, paper)
	self:drawBookmark()
	self:drawScrollbar()
	self:drawPageNum()
	self:drawContents(40 + margin, self.position + self.offset, self.position + self.offset + 240)
	Graphics.termBlend()

	Graphics.initBlend(BOTTOM_SCREEN)
	Graphics.fillRect(0, 320, 0, 240, paper)
	self:drawContents(margin, self.position + self.offset + 240, self.position + self.offset + 480)
	Graphics.termBlend()

	Graphics.flip()

	self.dirty = false
end

-- CLASS: ImageRendeder
render.ImageRenderer = {}
render.ImageRenderer.__index = render.ImageRenderer
render.ImageRenderer.zoom_amount = 1.05
function render.ImageRenderer:new(image)
	local obj = {}
	setmetatable(obj, render.ImageRenderer)
	obj.image = image
	obj.width = Graphics.getImageWidth(image)
	obj.height = Graphics.getImageHeight(image)
	obj.x = obj.width / 2
	obj.y = obj.height / 2
	obj.min_scale = math.min(320 / obj.width, 240 / obj.height)
	obj.max_scale = 5
	obj.scale = obj.min_scale
	obj.dirty = true
	return obj
end

function render.ImageRenderer:scroll(x, y)
	self.x = self.x + x / self.scale
	self.y = self.y + y / self.scale

	self.x = math.max(0, math.min(self.x, self.width))
	self.y = math.max(0, math.min(self.y, self.height))

	self.dirty = true
end

function render.ImageRenderer:zoomIn()
	self.scale = self.scale * self.zoom_amount
	self.scale = math.max(self.min_scale, math.min(self.scale, self.max_scale))
	self.dirty = true
end

function render.ImageRenderer:zoomOut()
	self.scale = self.scale / self.zoom_amount
	self.scale = math.max(self.min_scale, math.min(self.scale, self.max_scale))
	self.dirty = true
end

function render.ImageRenderer:update()
end

function render.ImageRenderer:draw()
	Screen.waitVblankStart()
	if not self.dirty then
		return
	end

	local s = self.scale
	local x = self.x * s
	local y = self.y * s
	Graphics.initBlend(TOP_SCREEN)
	Graphics.drawScaleImage(200 - x, 360 - y, self.image, s, s)
	Graphics.termBlend()

	Graphics.initBlend(BOTTOM_SCREEN)
	Graphics.drawScaleImage(160 - x, 120 - y, self.image, s, s)
	Graphics.termBlend()

	Graphics.flip()

	self.dirty = false
end

return render
