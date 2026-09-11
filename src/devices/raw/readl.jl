#=
readl:
- Julia version: 
- Author: Computer
- Date: 2023-09-07
=#
function readl(s,stop='\n')
    acc = ""
    while true
        ch = read(s,Char)
        if ch == stop || ch == '\06'
            return chomp(acc)
        else
            acc=acc*ch
        end
    end
end