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

- [ ] update basalt version
- [ ] new job should rescan for new chest since server startup
- [ ] add job dependency ? (add output/input to job for chaining them)
- [ ] Handle items with nbt
  - [ ] Modify UI (button 1x1 on right, info frame x=4 on bottom)
  - [ ] Add keyCombo over items (Ctrl+key) for frequent job like smelting
- [ ] add administration tools (TUI or GUI) for add/remove jobs, chests, recipes
  - [ ] add pocket computer support for calling jobs remotely and admin server
- [ ] Add installation doc (and script ?)

## Issues

- [ ] When 2 recipes available, should use the other when the first is not
      available
- [ ] when no quantity set and press Enter, should default to one instead of
      crashing
- [ ] When requesting to many items, the programm send back some of them

## Ideas

A job should, like a recipe, take input and give output items.
Items when inserted (put) should queueEvent(itemName, ...) in order to trigger
job completion.
job and recipe of the same dependency level should be executed in parallele on
different crafting turtles.
Server should be a crafting turtle and only send the final recipe result to the
client.
job should be cancellable.

