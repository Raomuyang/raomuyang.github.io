.PHONY: before prepare

env:
	npm install -g hexo-cli
	npm install -g hexo-generator-sitemap
	npm install -g hexo-generator-baidu-sitemap
	npm install -g hexo-generator-searchdb
	npm install -g hexo-filter-mermaid-diagrams
	npm install -g hexo-generator-feed


prepare:
	mkdir -p ../blog-generate 
	hexo init ../blog-generate 
	rm -r ../blog-generate/source
	cp -r ./* ../blog-generate
	rm -r ../blog-generate/themes
	git clone --branch v7.6.0 --single-branch --depth 1 https://github.com/theme-next/hexo-theme-next.git ../blog-generate/themes/next
	find themes -type d|xargs -I{} mkdir -p ../blog-generate/{}
	find themes -type f|xargs -I{} cp {} ../blog-generate/{}

compile: prepare
	cd ../blog-generate && hexo g
