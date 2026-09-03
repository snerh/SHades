module Log
	#lk = ReentrantLock()
	function printlog(s...)
		#println(s...)
		#lock(lk)
		#Threads.@spawn (
		open("log.txt","a";lock=true) do io
			println(io,s...)
		end
		#)# Threads
		#unlock(lk)
	end
end
