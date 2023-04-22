# Inventory-manager

Manage your inventory with cc:tweaked
User interface is based of [Basalt](https://basalt.madefor.cc/#/)


## Features

### Inventory system

Request items
dump items to a central inventory


### Crafting

Save recipes
Craft items recursively


### Jobs

Create jobs to manipulate your inventory automatically or by a simple click
Job can include many tasks and can be called regularly or manually.


## Installation

TODO


## TODO

- [ ] finish liveParams features:
    - [ ] keyboard navigation
    - [ ] server removeJob option
    - [ ] handle frequency on cron job
    - [ ] newly added job need server restart to be active
    - [ ] factorize job/cron methods on server.lua
- [x] Fix bug when user input a wrong string in main input and press Enter/Get
- [ ] Add log when user ask too many crafts
- [ ] Handle count vs count in recipe if recipe provide more than one item
- [ ] Handle items with nbt
- [ ] add pocket computer support for calling jobs remotely
- [x] Use return value from callRemote to verify if get/put are ok
- [x] Clean code (remove unused function and utils.lua ?)
- [ ] Add installation doc (and script ?)
- [x] Add basalt to source
