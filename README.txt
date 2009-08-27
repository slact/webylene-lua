Webylene

1. Introduction
  Webylene is a MVC-ish web framework that tries to have a very small 
  learning curve to get started, doesn't tie your arms behind your back,
  
2. Directory Layout
  webylene root/
    bootstrap.lua - the bootstrap. don't mess with it.
    /objects      - objects dir. place objects you'll use here
      /core       - core objects. don't mess with them.
      /plugins    - plugin objects. place plugins here.
      /config     - config dir. place your config files here.
        /delayed  - place configs that shouldn't be autoloaded here
      /scripts    - page-specific scripts
                    put your scripts here. the router will map 
                    urls to scripts. see the router config.
    /templates    - templates (a.k.a. views) should be here
                    templates produce the actual output to browser.
    /web          - server root. only static content goes here
	  

3. Getting Started
  for development, invoke the bootstrap with something like 
  ./bootstrap.lua --path /home/username/my_webylene_project \
    --protocol fcgi --reload --env dev
  for details, see ./bootstrap.lua --help
	
  edit config/app.yaml - set database stuff and env stuff
  write scripts that handle requests to specific urls in scripts/
  route requests from desired urls to scripts in config/routes.yaml
  make templates in templates/
	
  
4. How does it work?
  wouldn't you like to know? (todo)
  
5. Who made it?
  Leo Ponomarev, sometime in 2008-2009.
  
6. What licence is it distributed under?
  The New BSD licence:
  
  Copyright (c) 2007-2009, Leo Ponomarev
  All rights reserved.

  Redistribution and use in source and binary forms, with or without 
  modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, 
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the 
      documentation and/or other materials provided with the distribution. 
    * The names of the authors may not be used to endorse or promote products 
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
