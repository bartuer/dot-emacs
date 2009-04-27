#name : class object
# --
+ (void) initialize;//move me to header
+ (void) initialize
{
  if (self == [${1:classname} class])
  {
    $0
  }
}