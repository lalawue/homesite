-- 
-- by lalawue, 2019/06/02
--

-- 
-- user defined function
-- 
local user = {
   projNames = nil,              -- table [projName][FileName]
   blogYearMonthFiles = nil,     -- blog YYYY-MM files
   isBlogSortFiles = false,      -- blog sorted YYYY-MM files   
   blogArchiveLinkContent = nil, -- blog archive links content
   blogTempContent = {},         -- index, category files
}

function user.writeFile( path, content )
   local f = io.open(path, "w")
   if f then
      f:write( content )
      f:close()
   end
end

function user.readFile( path )
   local f = io.open(path, "r")
   if f then
      local content = f:read("a")
      f:close(f)
      return content
   else
      return ""
   end
end

function user.mdGetTitle( config, proj, filename )
   -- '#title title', for <title> or <h1> tag
   local path = config.source .. "/" .. proj.dir .. "/" .. filename
   local content = config.user.readFile( path )
   if content then
      local name = content:match("#title ([^\n]+)\n")
      if name then
         return name
      else
         return filename
      end
   end
   return ""
end

function user.mdGenContentDesc( config, proj, content )
   -- '#contents depth-number'
   local s, e = content:find("\n#contents%s*")
   if not s then
      return content
   end
   local depth = content:match("\n#contents%s*(%d*)")
   if not depth then
      return content
   end
   local pre = content:sub(1, s - 1)
   local sub = content:sub(e + 1 + depth:len(), content:len())
   local lastStack = {}
   local lastNum = 0
   local firstNum = 0
   local index = 1
   local desc = ""
   sub = sub:gsub("\n(#+%s+[^%c]+)", function( mark )
                     local num = mark:find("%s")
                     if lastNum > 0 and num > depth then
                        return mark
                     end
                     if lastNum <= 0 then
                        depth = num + tonumber(depth) - 1
                        lastNum = num
                        desc = "<dl class=\"contents\">"
                        lastStack[#lastStack + 1] = "</dl>"
                     elseif num > lastNum then
                        lastNum = num
                        desc = desc .. "<dd><dl class=\"contents\">"
                        lastStack[#lastStack + 1] = "</dl></dd>"
                     elseif num < lastNum then
                        while lastNum > num and #lastStack > 0 do
                           lastNum = lastNum - 1
                           desc = desc .. lastStack[#lastStack]
                           table.remove(lastStack)
                        end
                     end
                     local title = mark:match("#+%s+([^%c]+)")
                     desc = desc .. string.format("<dt class=\"contents\"><a href=\"#sec-%d\">%s</a></dt>",
                                                  index, title)
                     local ret = string.format("<a id=\"sec-%d\"></a>\n%s", index, mark)
                     index = index + 1                           
                     return ret
   end)
   while #lastStack > 0 do
      desc = desc .. lastStack[#lastStack]
      table.remove(lastStack)
   end
   return pre .. desc .. "\n" .. sub
end

function user.mdReplaceTag( config, proj, content )
   -- replace [Desc](#footnote) to html tag
   local tags = {}
   content = content:gsub("(%[[^%]]-%]%(#[^%)]-%))", function( mark )
                             local name, fntag = mark:match("%[(.-)%]%(%#([^%)]-)%)")
                             if fntag and not tags[fntag] then
                                tags[fntag] = fntag
                                return string.format("<sup><a href=\"#%s\">%s</a></sup>", fntag, name)
                             else
                                return string.format("<sup>&lsqb;<a id=\"%s\">%s</a>&rsqb;</sup>", fntag, name)
                             end
   end)
   local projNames = config.user.projNames
   -- 
   -- replace [Desc](WikiTag) as really links, WikiTag may contain
   -- '#' as project/source/anchor seperator, for example:
   -- 
   -- 1. [Desc](ProjectSourceName)
   -- 2. [Desc](OtherProject#SourceName)
   -- 3. [Desc](OtherProject#SourceName#Anchor)
   return content:gsub("(%[[^%]]+%]%([^%)]+%))", function( mark )
                          local name, tag = mark:match("%[([^%]]+)%]%(([^%)]+)%)")
                          local ptag, ftag, atag = tag:match("([^#]+)#([^#]+)#([^%c]+)")
                          if ptag and ftag and atag then
                             return string.format("[%s](../%s/%s.html#%s)", name, ptag, ftag, atag)
                          end
                          local ptag, ftag = tag:match("([^#]+)#([^%c#]+)")
                          if ptag and ftag then
                             if projNames[ptag] and projNames[ptag][ftag] then
                                ftag = projNames[ptag][ftag]
                                return string.format("[%s](../%s/%s)", name, ptag, ftag)
                             end
                          end
                          local projFile = projNames[proj.dir][tag]
                          if projFile then
                             return string.format("[%s](%s)", name, projFile)
                          end
                          return string.format("[%s](%s)", name, tag)
   end)
end

function user.mdGenAnchor( config, proj, content )
   return content:gsub("\n#([^#%s%c]+)", function(mark)
                             return string.format("<a id=\"%s\"></a>\n", mark)
   end)
end

function user.blogGenDateTime( config, proj, content )
   local s, e = content:find("\n#date%s*")
   if not s then
      return content
   end
   content = content:gsub("\n(#date%s*[^%c]*)", function(mark)
                             local date = mark:match("#date%s*([^%c]*)")
                             return string.format("\n<div class=\"date\">%s</div>", date)
   end)
   return content
end

function user.blogGenCategory( config, proj, filename, content )
   local s, e = content:find("\n#category%s*")
   if not s then
      return content
   end
   -- '#p[0-9]+' is fixed title anchor for every entry
   local anchorName = content:gmatch("\n#(p%d+)")
   local categoryLink = function(mark)
      local name = mark:match("#category%s*(%a*)")
      local clink = string.format("<a href=\"Category%s.html\">Category%s</a>", name, name)
      local plink = string.format("<a href=\"%s.html#%s\">Permalink</a>", filename, anchorName())
      return string.format("\n<div class=\"category\">%s / %s</div>\n", clink, plink)
   end
   content = content:gsub("\n(#category%s*[^%c]*)", categoryLink)
   return content
end

function user.blogSortFiles( config, proj )
   if not config.user.blogYearMonthFiles then
      local fileList = {}
      for _, filename in ipairs(proj.files) do
         if filename:match("(%d+)%-(%d+)") then
            fileList[#fileList + 1] = filename
         end
      end
      table.sort(fileList, function(s1, s2)
                    local y1, m1 = s1:match("(%d+)%-(%d+)")
                    local y2, m2 = s2:match("(%d+)%-(%d+)")
                    if tonumber(y1) == tonumber(y2) then
                       return tonumber(m1) > tonumber(m2)
                    else
                       return tonumber(y1) > tonumber(y2)
                    end
      end)
      proj.files = fileList
      config.user.blogYearMonthFiles = fileList
   end
end

function user.blogGenArchiveLinks( config, proj )
   if config.user.blogArchiveLinkContent then
      return config.user.blogArchiveLinkContent
   end
   local nameList = {
      [1]="January", [2]="February", [3]="March", [4]="April",
      [5]="May", [6]="June", [7]="July", [8]="August",
      [9]="September", [10]="October", [11]="November", [12]="December"
   }
   local tbl = {}
   for _, filename in ipairs(config.user.blogYearMonthFiles) do
      local year, month = filename:match("(%d+)%-(%d+)")
      if year and month then
         tbl[#tbl+1] = string.format("<li><a href=\"%s.html\">%s %s</a></li>",
                                     filename, nameList[tonumber(month)],
                                     year)
      end
   end
   config.user.blogArchiveLinkContent =
      "<div class=\"archive_links\"><ul>" .. table.concat(tbl) .. "</ul></div>"
   return config.user.blogArchiveLinkContent
end

function user.blogCollectCategory( config, proj, filename, content )
   local s = filename:find("%d*%-%d*")
   if not s then
      return
   end
   local categoryTable = {}      
   local anchorName = content:gmatch("\n#(p%d+)")
   local dateName = content:gmatch("#date%s+([^%c]+)")
   local titleName = content:gmatch("##%s+([^%c]+)")
   local categoryName = content:gmatch("#category%s*(%a*)")

   while true do
      local cname = categoryName()
      if cname then
         local tbl = categoryTable[cname]
         if not tbl then
            tbl = {}
            categoryTable[cname] = tbl
            local year, month = filename:match("(%d+)%-(%d+)")
            tbl[#tbl + 1] = string.format("\n## %s.%s", year, month)
         end
         tbl[#tbl + 1] = string.format("- %s [%s](%s%s#%s)", dateName(),
                                       titleName(), filename, config.suffix, anchorName())
      else
         break
      end
   end

   for cname, tbl in pairs(categoryTable) do
      local name = "Category" .. cname
      local content = config.user.blogTempContent[name]
      if not content then
         content = string.format("\n#title Category %s\n", cname)
         proj.files[#proj.files + 1] = name
      end
      content = content .. table.concat(tbl, "\n")
      config.user.blogTempContent[name] = content
   end
end

function user.blogGenWelcomePage( config, proj )
   local blogYearMonthFiles = config.user.blogYearMonthFiles
   local count = math.min(#blogYearMonthFiles, 11)
   if count <= 0 then
      return
   end
   local entries = {}   
   local sourcePath = config.source .. "/" .. proj.dir .. "/"
   -- generate welcome page
   for i=1, count, 1 do
      local content = config.user.readFile( sourcePath .. blogYearMonthFiles[i] )

      local as, ae, cs, ce = 0, 0, 0, 0
      repeat
         as, ae = content:find("\n(#p[^%c]+)", ce + 1)
         cs, ce = content:find("\n(#category[^%c]+)", ce + 1)
         if as and ae and cs and ce then
            entries[#entries + 1] = content:sub(as, ce)
         else
            break
         end
      until #entries >= count

      if #entries >= count then
         break
      end
   end
   if #entries > 0 then
      config.user.blogTempContent["index"] =
         "\n#title Welcome\n" .. table.concat(entries, "\n")
      proj.files[#proj.files + 1] = "index"
   end
end

function user.sitePrepare( config, proj )
   -- generage projNames[ProjDir][SourceName] = [Resouce | Source.html]
   local projNames = config.user.projNames
   if not projNames then
      projNames = {}
      for _, proj in ipairs(config.projs) do
         projNames[proj.dir] = {}
         for _, f in ipairs(proj.files) do
            if proj.res then
               projNames[proj.dir][f] = f
            else
               projNames[proj.dir][f] = f .. ".html"
            end
         end
      end
   end
   config.user.projNames = projNames
end

function user.siteBody( config, proj, filename, content )
   if content then
      content = content:gsub("#title ", "# Sucha's Homepage ~ ")
      content = config.user.mdGenContentDesc( config, proj, content )
      content = config.user.mdReplaceTag( config, proj, content )
      content = config.user.mdGenAnchor( config, proj, content )
      return content
   end
end

function user.siteHeader( config, proj, filename )
   local part1 = [[<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">
  <head>
    <title>Sucha's Homepage - ]]
   local part2 = config.user.mdGetTitle( config, proj, filename )
   local part3 = [[</title>
    <meta http-equiv="Content-Type" content=" text/html; charset=utf-8" />
    <meta name="author" content="Sucha" />
    <meta name="keywords" content="suchang, programming, GNU, Linux, Emacs" />
    <meta name="description" content="Sucha's homepage and blog" />
    <link rel="shortcut icon" href="../images/ico.png" />
    <link rel="stylesheet" type="text/css" href="../styles/site.css" />
    <link rel="alternate" type="application/rss+xml" title="RSS" href="../blog/rss.xml" />
    <!--[if lte IE 6]><link rel="stylesheet" type="text/css" href="../styles/ie.css" /><![endif]-->
  </head>
  <body>
    <div id="body">
      <div id="text">
	<!-- Page published by cmark-gfm begins here -->]]
      return part1 .. part2 .. part3
end

function user.siteFooter( config, proj, filename )
   return [[<!-- Page published by cmark-gfm ends here -->
      <div id="foot">
	2004-<script language="javascript">var d = new
	Date();document.write(d.getFullYear())</script> &copy;
	Sucha. Powered by MarkdownProjectCompositor.
      </div><!-- foot -->
      </div><!-- text -->
      <div id="sidebar">
	<p class="header">Here</p>
	<ul>
	  <li><a href="../index.html">Home</a></li>
	  <li><a href="index.html">Front</a></li>
	  <li><a href="../scratch/ThisSite.html">This Site</a></li>
	  <li><a href="../live/AboutMe.html">About Me</a></li>
	  <li><a href="../scratch/EmacsWiki.html">Emacs Wiki</a></li>
	</ul>
	<p class="header">Categories</p>
	<ul>
	  <li><a href="../blog/index.html">Blog</a></li>
	  <li><a href="../live/index.html">Life</a></li>
	  <li><a href="../cs/index.html">Lab</a></li>
	  <li><a href="../slack/index.html">Slackware</a></li>
	  <li><a href="../muse/index.html">Muse</a></li>
	  <li><a href="../scratch/index.html">Scratch</a></li>
	</ul>
	<p class="header">Search</p><!-- Bing Search -->
	<form id="searchform" method="get" action="http://cn.bing.com/search" >
	  <p><input id="searchtext" type="text" name="q" value="" /></p>
          <p><input type="hidden" name="ie" value="utf-8" /></p>
	  <p><input type="hidden" name="oe" value="utf-8" /></p>
	  <p><input type="hidden" name="hl" value="zh-CN" /></p>
 	  <p><input type="hidden" name="domains" value="suchang.net" /></p>
          <p><input name="si" type="hidden" value="suchang.net" /></p>
          <p><input type="hidden" name="sitesearch" value="suchang.net" /></p>
	</form>
	<p class="header">Contact</p>
	<ul>
	  <li><a href="mailto:suchaaa@gmail.com">Email Me</a></li>
	</ul>
      </div><!-- sidebar -->
    </div><!-- body -->
  </body>
</html>]]
end

function user.blogPrepare( config, proj )
   config.user.sitePrepare( config, proj )
   config.user.blogSortFiles( config, proj )
   config.user.blogGenArchiveLinks( config, proj )   
   config.user.blogGenWelcomePage( config, proj )   
end

function user.blogBody( config, proj, filename, content )
   content = content or config.user.blogTempContent[filename]
   if content then
      config.user.blogCollectCategory( config, proj, filename, content )
      content = content:gsub("#title ", "# Sucha's Blog ~ ")
      content = config.user.blogGenDateTime( config, proj, content )
      content = config.user.blogGenCategory( config, proj, filename, content )
      content = config.user.mdReplaceTag( config, proj, content )
      content = config.user.mdGenAnchor( config, proj, content )
      return content
   end
end

function user.blogHeader( config, proj, filename )
   local part1 = [[<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">
  <head>
    <title>Sucha's Blog - ]]
   local part2 = config.user.mdGetTitle( config, proj, filename )
   local part3 = [[</title>
    <meta name="generator" content="MarkdownProjectCompositor.lua" />
    <meta http-equiv="Content-Type" content=" text/html; charset=utf-8" />
    <meta name="author" content="Sucha" />
    <meta name="keywords" content="suchang, programming, GNU, Linux, Emacs, elisp" />
    <meta name="description" content="Sucha's blog" />
    <link rev="made" href="mailto:suchaaa@gmail.com" />
    <link rel="shortcut icon" href="../images/ico.png" />
    <link rel="stylesheet" type="text/css" href="../styles/blog.css" />
    <!--[if lte IE 6]><link rel="stylesheet" type="text/css" href="../styles/ie.css" /><![endif]-->
  </head>
  <body>
    <div id="body">
      <div id="text">
	<!-- Page published by cmark-gfm begins here -->]]
      return part1 .. part2 .. part3
end

function user.blogFooter( config, proj, filename )
   local part1 = [[<!-- Page published by cmark-gfm ends here -->
<div id="foot">2004-<script language="javascript">var d = new
	Date();document.write(d.getFullYear())</script> &copy;
	Sucha. Powered by MarkdownProjectCompositor.
</div>
</div><!-- sidebar -->
  <div id="sidebar">
      <p class="header">Here</p>
      <ul>
        <li><a href="../index.html">Home</a></li>
        <li><a href="index.html">Front</a></li>
        <li><a href="../scratch/ThisSite.html">This Site</a></li>
        <li><a href="../live/AboutMe.html">About Me</a></li>
        <li><a href="../cs/EmacsWikiJournal.html">Emacs Wiki Journal</a></li>
      </ul>

      <p class="header">Search</p><!-- Bing Search -->
      <form id="searchform" method="get" action="http://cn.bing.com/search" >
	<p><input id="searchtext" type="text" name="q" value="" /></p>
	<p><input type="hidden" name="ie" value="utf-8" /></p>
	<p><input type="hidden" name="oe" value="utf-8" /></p>
	<p><input type="hidden" name="hl" value="zh-CN" /></p>
	<p><input type="hidden" name="domains" value="suchang.net" /></p>
	<p><input name="si" type="hidden" value="suchang.net" /></p>
	<p><input type="hidden" name="sitesearch" value="suchang.net" /></p>
      </form>

      <p class="header">Contact</p>
        <ul>
          <li><a href="mailto:suchaaa@gmail.com">Mail me</a></li>
        </ul>

      <p class="header">Categories</p>

      <ul>
        <li><a href="CategoryLinux.html">GNU/Linux</a></li>
        <li><a href="CategoryProgramming.html">Programming</a></li>
        <li><a href="CategoryLife.html">Life &#38; essay</a></li>
        <li><a href="CategoryReading.html">Reading</a></li>
	<li><a href="CategoryThisSite.html">This Site</a></li>
        <li><a href="CategoryMisc.html">Misc</a></li>
      </ul>

      <p class="header">Links</p>
      <ul>
      <li><a href="http://blog.csdn.net/g9yuayon/">G9</a></li>
        <li><a href="http://mrjamie.cc/">Jamie</a></li>
        <li><a href="http://www.ftchinese.com/column/007000002">朝九晚五</a></li>
        <li><a href="http://blog.codingnow.com/">CloudWu</a></li>
        <li><a href="http://ditu.google.cn/maps?hl=zh-CN&ll=22.626687,110.186691&spn=0.101883,0.15398&t=h&brcurrent=3,0x36adc425dfd47083:0xd77004f2b5f175d6,0,0x36adb6981be5ba57:0xbb22df1016a0dd2e%3B5,0,0&z=13">Yulin in Google Maps</a></li>
      </ul>

      <p class="header">Archives</p>]]
   local part2 = config.user.blogGenArchiveLinks( config, proj )
   local part3 = [[</div><!-- sidebar -->
   </div> <!-- body -->
  </body>
</html>]]
   return part1 .. part2 .. part3
end

--
-- config for MarkdownProjectCompositor
-- 
local config = {
   source = "source",
   build = "publish",
   suffix = ".html",
   program = "cmark-gfm",
   params = " -t html --unsafe --github-pre-lang ",
   tmpfile = "/tmp/MarkdownProjectCompositorTempFile",
   projs = {},
   user = user,
}

-- define projects
config.projs = {
   {
      res = true,               -- resouces dir, no build
      dir = "images",           -- dir under build path
   },
   {
      res = true,
      dir = "doc",
      files = {},              -- proj source filled by compositor
   },
   {
      res = true,
      dir = "code",
      files = {},
   },   
   {
      dir = "scratch",
      files = {},
      prepare = user.sitePrepare,
      body = user.siteBody,
      header = user.siteHeader,
      footer = user.siteFooter,
   },
   {
      dir = "muse",
      files = {},
      prepare = user.sitePrepare,
      body = user.siteBody,
      header = user.siteHeader,
      footer = user.siteFooter,
   },
   {
      dir = "live",
      files = {},
      prepare = user.sitePrepare,
      body = user.siteBody,
      header = user.siteHeader,
      footer = user.siteFooter,
   },
   {
      dir = "slack",
      files = {},
      prepare = user.sitePrepare,
      body = user.siteBody,
      header = user.siteHeader,
      footer = user.siteFooter,
   },
   {
      dir = "cs",
      files = {},
      prepare = user.sitePrepare,
      body = user.siteBody,
      header = user.siteHeader,
      footer = user.siteFooter,
   },
   {
      dir = "blog",
      files = {},
      prepare = user.blogPrepare,  
      body = user.blogBody,
      header = user.blogHeader,
      footer = user.blogFooter,
   }
}

-- return this table as config
return config