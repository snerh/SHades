module Log
	function printlog(s...)
		#println(s...)
		Threads.@spawn ( open("log.txt","a";lock=true) do io
			println(io,s...)
		end)
	end
end
