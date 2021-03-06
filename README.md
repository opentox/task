OpenTox Task
============

- An [OpenTox](http://www.opentox.org) REST Webservice 

REST operations
---------------

    Get a list of all tasks     GET     /                 -                       Task URIs                             200
    Get the status of a  task   GET     /{id}/status      -                       created|started|completed|cancelled   200,404
    Get the PID of a  task      GET     /{id}/pid         -                       Task PID                              200,404
    Create a new task           POST    /                 -                       Task URI                              200
    Start a  task               PUT     /{id}/started     ""                      -                                     200,404
    Complete a  task            PUT     /{id}/completed   resource={resource_uri} -                                     200,404
    Set the PID of a  task      PUT     /{id}/pid         pid={PID}               -                                     200,404
    Cancel a  task              PUT     /{id}/cancelled   ""                      -                                     200, 404
    Delete a  task              DELETE  /{id}             -                       -                                     200, 404
    Delete all  tasks           DELETE  /                 -                       -                                     200

IMPORTANT NOTE: Our framework does not accept empty PUT requests. Please send an empty parameter (e.g. with -d '' for curl) or you will receive a "411 Length Required" error.

[API documentation](http://rdoc.info/github/opentox/task)
--------------------------------------------------------

Copyright (c) 2009-2011 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.

