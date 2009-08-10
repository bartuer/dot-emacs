# name : js partial render controller api rails
# (link "/Users/bartuer/local/src/rails/actionpack/test/controller/render_test.rb" 6115)
# (link "/Users/bartuer/local/src/rails/actionpack/test/controller/render_test.rb" 26088)
# (rdoc "ActionController::Base#render")
# (yas/tap) render, :js 'source', :location 'url'
# --
render ${1:`(yas/p ":js" "'source'")`}$0, ${2:`(yas/p ":location" ":action")`}
