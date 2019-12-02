# example

Geopackage Example App

# VERY IMPORTANT REGARDING THE EXAMPLE APP

The example app works only on Android due to its dependence on the storage path 
of the test geopackage database. IOS users will need to change the path from which
the geopackage database is pulled. No big issue, but it is not automatic yet (pull 
requests are welcome, I don't really care about IOS at the time being, so it might 
take a while before I do it).

For the example to work, you need to copy the **gdal_sample.gpkg** file that is in the test folder of the 
main library (flutter_geopackage) to the main storage of the device, i.e. it has to be available 
in **/storage/emulated/0/gdal_sample.gpkg** since the path is hardcoded (see above comment).
