((;
  uniqid = (2 + 3                          );
  $stderr.puts("!UNIQID![1] => " + uniqid.class.to_s + " " + uniqid.inspect) || begin;
  $stderr.puts local_variables;
  local_variables.each{|__uniqid|;
    ___uniqid = eval(__uniqid);
    if uniqid == ___uniqid && __uniqid != %2 + 3                          .strip;
      $stderr.puts("!UNIQID![1] ==> " + __uniqid);
    elsif [___uniqid] == uniqid;
      $stderr.puts("!UNIQID![1] ==> [" + __uniqid + "]");
    end;
  };
  nil;
rescue Exception;
  nil;
end || uniqid;
));

# stderr
# puts

# class
# to_s
# inpect
# eval
# begin
# rescue
# strip
# local_variables
