set :stage, :production

server "#{host}", roles: [:nginx], user: "#{user}"
server "#{host}", roles: [:sinatra], user: "#{user}"
server "#{host}", roles: [:db], user: "#{user}"