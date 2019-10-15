.PHONY: before prepare

env:
	npm install -g hexo-cli
	npm install --save hexo-generator-sitemap
	npm install --save hexo-generator-baidu-sitemap

prepare:
	mkdir -p ../blog-generate 
	hexo init ../blog-generate 
	rm -r ../blog-generate/source
	cp -r ./* ../blog-generate
	rm -r ../blog-generate/themes
	git clone https://github.com/raomuyang/hexo-theme-next ../blog-generate/themes/next
	find themes -type d|xargs -I{} mkdir -p ../blog-generate/{}
	find themes -type f|xargs -I{} cp {} ../blog-generate/{}

compile: prepare
	cd ../blog-generate && hexo g
