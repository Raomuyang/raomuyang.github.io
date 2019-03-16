.PHONY: before prepare

env:
	npm install -g hexo-cli
	npm install -g hexo-generator-sitemap
	npm install -g hexo-generator-baidu-sitemap

before:
	npm install -g hexo-cli
	npm install -g hexo-generator-sitemap
	npm install -g hexo-generator-baidu-sitemap

prepare:
	mkdir -p ../blog-generate 
	hexo init ../blog-generate 
	rm -r ../blog-generate/source
	cp -r ./* ../blog-generate
	git clone https://github.com/raomuyang/hexo-theme-next ../blog-generate/themes/next
	cp theme_config.yml ../blog-generate/themes/next/_config.yml

compile: prepare
	cd ../blog-generate && hexo g
