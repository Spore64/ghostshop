local GhostShop = RegisterMod("Ghost Shop", 1);
GhostShopMod = {}
local game = Game()

-- save data
local GameState = {}
local json = require("json")


--effects
EffectVariant.GHOST_STORE_SIGN = Isaac.GetEntityVariantByName("Ghost Store Sign")
EffectVariant.REFLECTED_STORE_SIGN = Isaac.GetEntityVariantByName("Reflected Store Sign")
EffectVariant.FLIP_EFFECT = Isaac.GetEntityVariantByName("Flip Effect")
GhostShopMod.ENTITY_GS_COOP_GHOST = Isaac.GetEntityTypeByName("GS Coop Ghost")

-- ghot signs are the home of little shop ghosts, however between entering and exiting the shop they might switch signs/places
local numLittleGhosts = 0	-- keeps track on how many possessed ghost signs should be spawned by reentering the shop
local SpawnGhostSigns = false 	-- 'true' if shop signs should be spawned

local currentItemPosition = {}	
local curItemQuality = {}
local IsNoShopItem = false		

-- things which need to get set in general
-- layouts
local shopLayouts = {
	{4, Vector(440,320), Vector(360,320), Vector(280,320), Vector(200,320)},				   -- {num items, item1, item2, ...} / unlucky layout
	{5, Vector(470,245), Vector(320,245), Vector(170,245), Vector(395,350), Vector(245,350)},		   -- {num items, item1, item2, ...}
	{5, Vector(470,350), Vector(320,350), Vector(170,350), Vector(395,245), Vector(245,245)},		   -- {num items, item1, item2, ...}
	{5, Vector(490,320), Vector(405,320), Vector(320,320), Vector(235,320), Vector(150,320)},		   -- {num items, item1, item2, ...} 
	{6, Vector(475,250), Vector(365,250), Vector(275,250), Vector(165,250), Vector(420,345), Vector(220,345)}  -- {num items, item1, item2, ...} / lucky layout
}
local numCollectibles = 832

-- things which need to get reset upon starting a new run
local NormalShopVisit = false	-- 'true' if the player entered the normal shop
local GhostShopVisit = false	-- 'true' if the player entered the Mirror shop
-- layouts
local usedLayout = 0		-- saves which shop layout is used for the ghost shop
	
-- extra bonuses
local luckyBonus = 0		-- depends on the player getting the lucky shop layout. Is always a + 4 (~ 1 quality)
local hasWon = false		-- true if an end game boss is beaten
local deathBonus = 0		-- depends on the amount of stages the player cleared before dying. Increases the item quality
local winBonus = 0		-- depends on which end boss the player managed to beat. Will reset deathbonus to 0.

-- general quality
local itemQuality = {}		-- stores the differnet item qualities. The table position correlates with the shopLayout table position + 1
local fixedQuality = 3		-- item position which always has a fixed quality from 3-4

-- things which need to get reset upon ending a run
-- item storage 
local storedItems = {		-- stores the items from the last run	
	{},			-- items of the quality 0
	{},			-- items of the quality 1
	{},			-- items of the quality 2
	{},			-- items of the quality 3
	{}			-- items of the quality 4
}
local storedCoopItems = {
	{},			-- items of player 2
	{},			-- items of player 3
	{}			-- items of player 4
}
local temporaryStored = {	-- stores the items for the players upon entering a new floor (used in case one or more players die as a coop baby or in the Mother Chase)
	{},			-- player 
	{},			-- coop1
	{},			-- coop2
	{}			-- coop3
}
local storeSigns = {}
local storeSignsFlipped = {}

-- item prices
local prePrice = {}		-- keeps track of the amount of the normal price in the pre flipped shop
local postPrice = {}		-- keeps track of the amount of the normal price in the post flipped shop
local shoppingList = {}		-- keeps track of the items you bought
local backupListOne = {}	-- keeps track of the items you bought overall in your run. Stores the items you bought 1 time in a row
local backupListTwo = {} 	-- keeps track of the items you bought overall in your run. Stores the items you bought 2 or more times in a row

-- synergies variables
local hasUsedDice = false	-- keeps track if a player used the D6, Eternal D6, D Infinty and Dice Shard
local hasUsedD100 = false	-- separatly keeps track if the player has used the D100, due to the bug with multiple items
local hasUsedD7 = false		-- keeps track if the player has used the D7
local hasUsedFlip = false	-- keeps track if a player used the Flip item
local hasUsedFMN = false	-- keeps track if a player used Forget Me Now. 'true' will prevent other item to get added to the preflipped table
local hasUsedMyGi = {false}	-- keeps track if a player used the Mystery Gift. hasUsedMyGi[1] == 'true' will trigger code in the 'MC_POST_PICKUP_INIT' callback to morph the newly spawned item
local hasUsedFMN = false	-- keeps track if Forget Me Now was used 
local hasSteamSale = false	-- keeps track if a player has a Steam Sale
local hasGlitchedCrown = false

local rerollTable = {}		-- keeps track of the item ID of the to be rerolled item
local rerollPosition = {}	-- keeps track of the position of the to be rerolled item
local searchedPosition = nil

local flipped = 1		-- keeps track if a player flipped the items and on which flipped site we are on currently 1 = normal 2 = flipped
local preFlipped = {}		-- stores the items of the regular layout of the ghost shop
local postFlipped = {}		-- stores the items of the version of layout of the ghost shop once the player uses the Flip item
local preTemporary = {}		-- restores the preFlipped table after the players uses the Glowing Hourglass

local usedFlipTable = nil	-- keeps track if Flip was used. (preFlipped) for the regular layout, (postFlipped) for the flipped layout
local usedShopSignTable = nil	-- keeps track if Flip was used ..... ?
local usedPriceTable = nil	-- keeps track if Flip was used. (prePrice) as the regular layout, (postPrice) as the flipped layout
local usedRestockTable = nil	-- keeps track if Flip was used. (preAddRestockPrice) for the regular layout, (postAddRestockPrice) for the flipped layout

local dontRestock = false
local needsToRestock = false

local preAddRestockPrice = {}	-- keeps track of the amount of money which should be added on top of the normal price in the pre flipped shop
local postAddRestockPrice = {}	-- keeps track of the amount of money which should be added on top of the normal price in the post flipped shop

local seenCollectibles = {}	-- keeps track of all the items spawned in in a run

local openNomralShop = false 	-- if the player visited the Ghost shop the other should be open. Only works in none hostile rooms
local shopStayOpen = false	-- keeps track if the shop door has played the opening animation and should stay open now

-- local spawnedCoopGhosts = 0	-- necessary?

-- ---------------------------- --
-- modded items compatibility :X --
local function ghostShop_ModCompatibility()
	numCollectibles = 832	-- reset the number of items before readding the extra amount of items
	-- check if major mods have been added since the last time (despite the savesystem not working with Custom Stage API)
	if FiendFolio then
		numCollectibles = numCollectibles + 159
	end
	if REVEL then
		numCollectibles = numCollectibles + 61
	end
	if Epiphany then
		numCollectibles = numCollectibles + 35
	end
	if IpecacMod then
		numCollectibles = numCollectibles + 120
	end
	-- print(numCollectibles)
end

local function ghostShop_ItemCompatibility(update)
	local currentTable = {}			-- stores the current table content

	if update == 1 then			-- check if all items in the tables are items which are still available
		for k = 1, 5 do 	-- go through each of the five tables
			if storedItems[k][1] ~= nil then
				for m, item in ipairs(storedItems[k]) do	-- go through each entry of the table
					
					if Isaac.GetItemConfig():GetCollectible(item) ~= nil then		-- check if the modded item is still available
						-- add the item to the currentTable table
						table.insert(currentTable,1,item)
					end
				end
				-- update the item table with the items which are still available
				storedItems[k] = currentTable
				-- reset the current table
				currentTable = {}
			end
		end
		for n = 1, 3 do 	-- go through each of the five tables
			if storedCoopItems[n][1] ~= nil then
				for o, item in ipairs(storedCoopItems[n]) do	-- go through each entry of the table
					if Isaac.GetItemConfig():GetCollectible(item) ~= nil then		-- check if the modded item is still available
						-- add the item to the currentTable table
						table.insert(currentTable,1,item)
					end
				end
				-- update the item table with the items which are still available
				storedCoopItems[n] = currentTable
				-- reset the current table
				currentTable = {}
			end
		end
	elseif update == 2 then			-- remove all modded items from the tables
		for k = 1, 5 do 	-- go through each of the five tables
			if storedItems[k][1] ~= nil then
				for m, item in ipairs(storedItems[k]) do	-- go through each entry of the table
					if item < 733 then			-- all items above 732 items are modded items
						-- add the item to the currentTable table
						table.insert(currentTable,1,item)
					end
				end
			
				-- update the item table with the items which are still available
				storedItems[k] = currentTable
				-- reset the current table
				currentTable = {}
			end
		end
		for n = 1, 3 do 	-- go through each of the five tables
			if storedCoopItems[n][1] ~= nil then
				for o, item in ipairs(storedCoopItems[n]) do	-- go through each entry of the table
					if item < 733 then			-- all items above 732 items are modded items
						-- add the item to the currentTable table
						table.insert(currentTable,1,item)
					end
				end
				-- update the item table with the items which are still available
				storedCoopItems[k] = currentTable
				-- reset the current table
				currentTable = {}
			end
		end
	end
	-- update the json tables once an invalid item has been found
	GameState.backupItems1 = storedItems[1]
	GameState.backupItems2 = storedItems[2]
	GameState.backupItems3 = storedItems[3]
	GameState.backupItems4 = storedItems[4]
	GameState.backupItems5 = storedItems[5]

	GameState.backUpCoopItems1 = storedCoopItems[1]
	GameState.backUpCoopItems2 = storedCoopItems[2]
	GameState.backUpCoopItems3 = storedCoopItems[3]
end

-- -------------------- --
-- ghost shop functions --

local function ghostShop_checkShoppingList()
	shoppingList = GameState.shoppingList
	backupListOne = GameState.backupShoppingListOne
	backupListTwo = GameState.backupShoppingListTwo
		
	if shoppingList[1] ~= nil then			-- first make sure the table isn't empty
		local decoyListOne = {}			-- stores item from the second one which match with the shoppingList
		local decoyListTwo = {}	
		local decoyListThree = {}		
		local readdItems = false 
			
		if backupListOne[1] == nil 
		and backupListTwo[1] == nil then	-- both tables are empty
			backupListOne = shoppingList	-- since they don't contain any items all items from the shoppingList get inserted into the frist backip table

		else	-- we split the items and insert them into the two backup tables
			for j, item in ipairs(shoppingList) do	-- go through each entry of the table
				local inSecondTable = false
				local inFirstTable = false
				-- for each entry of the shoppingList go through the items from the two backup shopping lists

				if backupListTwo[1] ~= nil then
					for k, backupItems in ipairs(backupListTwo) do
						if backupItems == item then
							-- add the item to the decoyListThree table
							table.insert(decoyListThree,1,item)
							-- marked the item id as being found
							inSecondTable = true
						end
					end
				end
				if inSecondTable == false		-- item wasn't in the second backup table
				and backupListOne[1] ~= nil then
					for l, backupItems in ipairs(backupListOne) do
						if backupItems == item then
							-- add the item to the decoyListTwo table
							table.insert(decoyListThree,1,item)
							-- marked the item id as being found
							inFirstTable = true
						end
					end
				end
				if inSecondTable == false
				and inFirstTable == false then
					-- add the item to the decoyListTwo table
					table.insert(decoyListOne,1,item)
				end
			end
			readdItems = true
		end
		if readdItems == true then
			-- reinsert the decoy tables
			backupListOne = decoyListTwo
			backupListTwo = decoyListThree
			-- insert the rest of the items into the first backup table
			if decoyListOne[1] ~= nil then		 	-- make sure the table isn't empty
				for m, item in ipairs(decoyListOne) do	-- go through the rest of the normal list
					table.insert(backupListOne,1,item)
				end
			end
		end
	elseif shoppingList[1] == nil then	-- no items have been bought in the last run
		-- reset both backup tables
		backupListOne = {}
		backupListTwo = {}
	end
	-- reset the shoppingList
	shoppingList = {}
end

local function ghostShop_SpawnGhostSign(position, chance)
	local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, position, Vector(0,0), nil):ToEffect()
	if shopSign:GetData().IsPossessed == nil then
		local ghostRoll = math.random(1,chance)
		if ghostRoll == 1 then	-- a possessed sign should be spawned
			shopSign:GetData().IsPossessed = true
			numLittleGhosts = numLittleGhosts + 1	-- adjust the number of little ghost which should be spawned on revisting the shop
		end
	end
end

local function ghostShop_ChoseNewItem(rng, quality, roll, item, spawnSign, addPrice, restock, reroll, spawnItem)			-- used to chose the items which have to be spawned. 
	local decoyTable = {}		-- stores the item which the players don't have at the moment
	local chosenItem = nil		-- stores the item Id of the item which should be spawnned in the end
	local preChosenItem = {}	-- stores the item Id of the item which got originally chosen to be spawned, but first have to be checked if it is a vailable option first
	local numTotalItems = 0
	local tablesChecked = 1
	local curTotalRemovedItems = 0

	-- Do the players have the item? ---------------------------------------------------------------------------------------------------------------

	while decoyTable[1] == nil and tablesChecked ~= 5 do		-- while the decoy table is still empty and all 5 tables haven't been checked
		if storedItems[quality][1] ~= nil then 			-- needs to be checked, because we could have decreased the quality again
			-- first we have to check which items the players from the current quality table already have
			-- we also need to get the current amount of items in the og table
			for a, curItem in ipairs(storedItems[quality]) do	-- go through each entry of the current quality table
				local playerHasCurItem = false

				for j = 0, (game:GetNumPlayers() - 1) do
					local player = Isaac.GetPlayer(j)
					-- check if the player has the item
					if player:IsCoopGhost() == false
					and player:HasCollectible(curItem) then
						playerHasCurItem = true
					end
				end
				if playerHasCurItem == false then		-- none of the players have the item currently
					numTotalItems = numTotalItems + 1	-- increase the number of items held in the decoy table
					table.insert(decoyTable, curItem)	-- insert the items into the decoy table
				end
			end
		end

		-- check if the decoy table empty or not (if empty than the players have the current items already)
		if decoyTable[1] == nil then
			-- check if we are already at the quality 0 table
			if quality == 1 then 	-- all tables have been checked (here 1 means 0)
				-- increase the number of tables we checked, so that the while loop breaks next round
				tablesChecked = 5

				if reroll == 1 then		-- 1 == true, in case of rerolling the existing item gets removed before a shop sign is even spawned
					item:Remove() 		-- first remove the shop item which is still there			
				end 

				if spawnSign == 1 then 	-- 1 == true, used in order to make the function universal

					-- this also means that we won't spawn an item at all. So we need to spawn a ghost sign
					ghostShop_SpawnGhostSign(shopLayouts[usedLayout][roll + 1], 3)	-- ghostShop_SpawnGhostSign(spawn position)

					if restock == 1 		-- 1 == true, in case of rerolling or restocking the shopSign should simply get added to the usedFlip table
					or reroll == 1 then	
						-- insert the ghost sign in the postFlipped table
						usedFlipTable[roll] = -1
						-- add a placeholder price on this postion
						usedPriceTable[roll] = -99	
					else
						-- insert the ghost sign in the usedFlipTable table
						table.insert(usedFlipTable, -1)
						-- add a placeholder price on this postion
						table.insert(usedPriceTable, -99)
					end
					
				else		-- Flip, Mystery gift as well as rerolling items which are not shop items
					if item ~= nil			-- item only equals something other than 0 for Mystery Gift and the Dice [...]
					and item == 0 then		-- so if it is 0, then it will be triggered through the Flipp item and a shopSign has to be added to the table
						-- insert the ghost sign in the usedFlipTable table
						table.insert(usedFlipTable, -1)
						-- add a placeholder price on this postion
						table.insert(usedPriceTable, -99)
					else
						-- in the other case we have to check if this was done by a Mystery Gift use
						if hasUsedMyGi[3] ~= nil then		-- 0 = false, in case of the mystery gift the item gets transformed into the poop, but reroll has tobe checked due the else function being triggered other ways as well
							item:ToPickup():Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_POOP, false)
						end
						-- for rerolling items which are not shop items
						if reroll == 2 then		-- 2 == true, reroll items outside of the slots
							
							local level = game:GetLevel()
							local stage = level:GetStage()
							local stageType = level:GetStageType()

							
							-- then get the stage the player is on 
							if stageType == StageType.STAGETYPE_REPENTANCE then		-- Downpour
								local lilghost = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.LIL_GHOST, 0, searchedPosition, Vector(0,0),nil):ToEffect()
							elseif stageType == StageType.STAGETYPE_REPENTANCE_B then	-- Dross
								Isaac.GridSpawn(GridEntityType.GRID_POOP, 0, searchedPosition, true)
							end
						end
					end
				end
			else 
				-- we need to check       quality table and thus decrease the quality by one
				quality = quality - 1
			end
		-- else the while loop breaks next round and we can progress
		end
	end

	-- Have the players seen the item? --------------------------------------------------------------------------------------------------------------

	if decoyTable[1] ~= nil then		-- if there are items to chose from
		-- we have at least one item in the table, so we can try to spawn something!
		local itemPosition = rng:RandomInt(#decoyTable) + 1
		local poolRNG = decoyTable[itemPosition]

		-- check if the table contains more than one item
		if decoyTable[2] ~= nil then	-- if yes then...

			-- we still need to see if the players have seen the item
			while chosenItem == nil and curTotalRemovedItems ~= numTotalItems do	-- loops while we haven't found and item to spawn yet and we haven't checked all
												-- the items in the table (numTotalItems)
				local hasSeenItem = false
	
				if seenCollectibles[1] ~= nil then
					for b, seenItem in ipairs(seenCollectibles) do	-- go through each entry of the table of the items the player have seen
						if seenItem == poolRNG then		-- if the item Id matches the supposed to spawned item Id then
											-- we to look for another vialable item ID

							-- tho we need to try to insert the item ID into the preChosenItem table in case this was the first item selected and all other items have been seen as well.
							if preChosenItem[1] == nil then	-- no other items have been inserted into the table yet
								table.insert(preChosenItem, poolRNG)
							end
							-- for that we have to remove the item first from the decoy table
							if decoyTable[itemPosition] ~= nil then		-- there's still one item left
								table.remove(decoyTable,itemPosition)		
							end
							-- then we increase the current number of removed items from the decoy table ('curTotalRemovedItems')
							curTotalRemovedItems = curTotalRemovedItems + 1		-- the while loop breaks in case it equals the variable 'numTotalItems'

							-- then we have to make sure that the new item ID doesn't get passed into the 'chosenItem' variable
							hasSeenItem = true
						end 
					end
				end

				-- the 'for'-loop found out that the seen item equals the item id we want to spawn
				if hasSeenItem == true then
					-- we try to chose a new item from the (now reduced) decoy table

					if decoyTable[2] ~= nil then
						itemPosition = rng:RandomInt(#decoyTable) + 1
						poolRNG = decoyTable[itemPosition]
					else
						if decoyTable[1] ~= nil then		-- there's still one item left
							poolRNG = decoyTable[1]			
						end
					end
					-- the new item id should now be used in the next iteration of the 'for'-loop
					-- print(poolRNG)
				end

				-- if the 'for'-loop hasn't found a match then we pass the original chosen item ID on
				-- if it found one, then this won't get triggered, as 'hasSeenItem is set to 'true' now
				if hasSeenItem == false then
					chosenItem = poolRNG			-- also the 'while'-loop should break, as 'chosenItem' isn't nil anymore
				end
			end
			-- we still need to check if curTotalRemovedItems equals numTotalItems now. If it does, then we will have to pass the originally chosen item on
			if curTotalRemovedItems >= numTotalItems 
			and preChosenItem[1] ~= nil then		-- only to make sure everything worked and the table ins't empty
				chosenItem = preChosenItem[1]
			end
		else
			chosenItem = poolRNG 	-- pass the item ID in order to spawn the item, yeah!
		end
	end

	-- How much does the item cost? ---------------------------------------------------------------------------------------------------------------

	if chosenItem ~= nil then	-- we check if an item as actually been selected from the decooy table. 
		-- now we can chose a prize for the item before we spawn it. For that we take the final 'quality' value and later the chosen item ID
		-- shop price
		local shopPrice = 15

		if addPrice == 1 then	-- 1 == true, could only be used when the item is spawned, but this probably save computing power
					
			-- determine the price baseed on the item quality
			if quality < 4 then	-- = quality 0,1 and 2
				shopPrice = shopPrice + (usedRestockTable[roll] * 2)
				usedPriceTable[roll] = shopPrice
			elseif quality == 4 then	-- = quality 3
				local priceRNG = rng:RandomInt(6)	-- + 5
				shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG
				usedPriceTable[roll] = shopPrice
			elseif quality == 5 then	-- = quality 4
				local priceRNG = rng:RandomInt(11)	-- + 10
				shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG
				usedPriceTable[roll] = shopPrice
			end

			-- check if the item was bought in the last run
			local foundItem = false
			if backupListOne[1] ~= nil then
				for c, item in ipairs(backupListOne) do
					if item == chosenItem then
						foundItem = true
						-- reevaluate the price
						shopPrice = 20
						if quality < 4 then	-- = quality 0,1 and 2
							usedPriceTable[roll] = shopPrice + (usedRestockTable[roll] * 2)	 -- store the new shop price
						elseif quality == 4 then	-- = quality 3
							local priceRNG = rng:RandomInt(6)	-- + 5
							shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG	 	-- costs between 20 - 25
							usedPriceTable[roll] = shopPrice
						elseif quality == 5 then	-- = quality 4
							local priceRNG = rng:RandomInt(11)	-- + 10
							shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG 	-- costs between 20 - 30
							usedPriceTable[roll] = shopPrice
						end
					end
				end
			end
			if foundItem == false		-- item wasn't in the first backup table
			and backupListTwo[1] ~= nil then
				for d, item in ipairs(backupListTwo) do
					if item == chosenItem then
						-- reevaluate the price
						shopPrice = 25
						if quality < 4 then	-- = quality 0,1 and 2
							usedPriceTable[roll] = shopPrice + (usedRestockTable[roll] * 2)	 	-- store the new shop price
						elseif quality == 4 then	-- = quality 3
							local priceRNG = rng:RandomInt(11)	-- + 10
							shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG	 	-- costs between 25 - 35
							usedPriceTable[roll] = shopPrice
						elseif quality == 5 then	-- = quality 4
							local priceRNG = rng:RandomInt(16)	-- + 15
							shopPrice = shopPrice + (usedRestockTable[roll] * 2) + priceRNG 	-- costs between 25 - 40
							usedPriceTable[roll] = shopPrice
						end
					end
				end
			end

			if hasSteamSale == true then
				shopPrice = math.floor(shopPrice / 2)
			end
		end

	-- Spawn the item! ---------------------------------------------------------------------------------------------------------------		

		if reroll == 1 	then	-- 1 == true, first it has to be check if an existing item should be rerolled into the choosen item
		
			usedFlipTable[roll] = chosenItem		-- simply add the items quality to the usedFlipped table

			-- morph the item to an item from the new quality table
			item:ToPickup():Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, chosenItem, false)
			if addPrice == 1 then	-- 1 == true, sometimes the prices doesn't have to be added
				item:ToPickup().AutoUpdatePrice = false
				item:ToPickup().Price = shopPrice
			end

		elseif reroll == 2 then	-- 2 == true, the choosen item is not a shop item
			local shopItem = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, chosenItem, searchedPosition, Vector(0,0), nil) -- :ToPickup()

		elseif hasUsedMyGi[3] ~= nil then
			-- morph the item to an item from the new quality table
			item:ToPickup():Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, chosenItem, false)

		else			-- if there's no existing item, then a new item has to be spawned
			-- add the items id to the usedFlipTable table
			if restock == 1 then
				usedFlipTable[roll] = chosenItem		-- simply add the items quality to the usedFlipped table
			else
				table.insert(usedFlipTable, chosenItem)		-- add a new entry to the usedFlipped table
			end

			if spawnItem == 1 then	-- 1 == true, check if an item should be spawned. In case of the first Flipp it prevents from the item being spawned
				-- then spawn the item
				local shopItem = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, chosenItem, shopLayouts[usedLayout][roll + 1], Vector(0,0), nil) -- :ToPickup()
				if addPrice == 1 then	-- 1 == true, sometimes the prices doesn't have to be added
					shopItem:ToPickup().AutoUpdatePrice = false
					shopItem:ToPickup().Price = shopPrice
				end
			end
		end
		
		-- all that is left is removing the item ID from the original 'storedItems[quality]'-table
		for e, ogItemID in ipairs(storedItems[quality]) do
			if ogItemID == chosenItem then
				-- remove the item from the table
				table.remove(storedItems[quality],e)
			end
		end
	end
end


local function ghostShop_FlipLayouts(rng, id, roll)	-- function used for the Flip synergy (ghostRNG, item id/or shop sign value, the roll from the for loop (i))
	local quality = 0
	local shopPrice = 0
	
	local itemConfig = Isaac.GetItemConfig()
 
	-- but first it has to be checked which layout table should be used
	if flipped == 1 then		-- it's the normal Layout
		usedFlipTable = preFlipped[roll]
		usedPriceTable = prePrice[roll]
	elseif flipped == 2 then	-- it's the flipped Layout
		usedFlipTable = postFlipped[roll]
		usedPriceTable = postPrice[roll]
	end
	-- check if a shop sign has to be spawn instead of an item
	if usedFlipTable == -1 then	-- it's a shop sign!
		if id == -1 then	-- no item id was passed into this function. Instead it has the value used for shop sign.
			local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, shopLayouts[usedLayout][roll + 1], Vector(0,0), nil):ToEffect()
			local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, shopSign.Position, Vector(0,0),shopSign):ToEffect()
			-- add the flip effect
			local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, Vector((shopSign.Position.X) + 12, (shopSign.Position.Y) - 17), Vector(0,0),shopSign):ToEffect()
			flipEffect:GetSprite():Play("Sign", true)

		else			-- id is the item id from an actual item!
			id:Remove()
			local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, shopLayouts[usedLayout][roll + 1], Vector(0,0), nil):ToEffect()
			local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, shopSign.Position, Vector(0,0),shopSign):ToEffect()
			-- add the flip effect
			local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, Vector((shopSign.Position.X) + 12, (shopSign.Position.Y) - 17), Vector(0,0),shopSign):ToEffect()
			flipEffect:GetSprite():Play("Questionmark", true)
		end
	else
		-- determine the quality of the qulaity of the item in question
		if itemConfig:GetCollectible(usedFlipTable).Quality == 0 then
			quality = 1	-- quality 0
		elseif itemConfig:GetCollectible(usedFlipTable).Quality == 1 then
			quality = 2
		elseif itemConfig:GetCollectible(usedFlipTable).Quality == 2 then
			quality = 3
		elseif itemConfig:GetCollectible(usedFlipTable).Quality == 3 then
			quality = 4
		elseif itemConfig:GetCollectible(usedFlipTable).Quality == 4 then
			quality = 5	-- quality 4
		end
		
		if id == -1 then	-- no item id was passed into this function. Instead it has the value used for shop sign.
			-- that means we don't have an item to morph and have to spawn the one from the table
			local shopItem = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, usedFlipTable, shopLayouts[usedLayout][roll + 1], Vector(0,0), nil):ToPickup()
			-- add the flip effect
			local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, Vector((shopItem.Position.X) + 12, (shopItem.Position.Y) - 18), Vector(0,0),shopItem):ToEffect()
			flipEffect:GetSprite():Play("Sign", true)

			if hasSteamSale == false then
				shopItem:ToPickup().AutoUpdatePrice = false
				shopItem:ToPickup().Price = usedPriceTable			-- set the price depending on the stored price of the choosen price table
			else
				shopItem:ToPickup().AutoUpdatePrice = false
				shopItem:ToPickup().Price = math.floor(usedPriceTable / 2)	-- set the price depending on the stored price of the choosen price table
			end
		else			-- id is the item id from an actual item!
			-- that means that it can be morph 
			id:ToPickup():Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, usedFlipTable, false)
			local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, id.Position, Vector(0,0),id):ToEffect()
			-- add the flip effect
			local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, Vector((id.Position.X) + 12, (id.Position.Y) - 18), Vector(0,0),id):ToEffect()
			flipEffect:GetSprite():Play("Questionmark", true)

			if hasSteamSale == false then
				id:ToPickup().AutoUpdatePrice = false
				id:ToPickup().Price = usedPriceTable			-- set the price depending on the stored price of the choosen price table
			else
				id:ToPickup().AutoUpdatePrice = false
				id:ToPickup().Price = math.floor(usedPriceTable / 2)	-- set the price depending on the stored price of the choosen price table
			end
		end
	end
end


local function ghostShop_SpawnCoopGhost(rng)
	local shopKeeperPositions = {}
	-- check if there are any shopkeepers in the room
	for _, entity in pairs(Isaac.GetRoomEntities()) do		
		if entity.Type == EntityType.ENTITY_SHOPKEEPER then
			-- insert the shopkeeper position into it's table. These will be the spawing points of the coop ghosts
			table.insert(shopKeeperPositions, entity.Position)
			-- print(shopKeeperPositions[1])
		end
	end
	-- check if at least one shopkeepers is in the room	
	if shopKeeperPositions[1] ~= nil then	
		for k = 1, 3 do		-- (1 = start, 3 = end, ... so it goes 1,2,3)
			-- check if the coop ghost table is emtpy or not
			if storedCoopItems[k][2] ~= nil then	-- the second place (and beyond) in the table stores the item the coop ghost can spawn.
				-- the first place stores the player Id also the identity of the coop ghost (for mod compatibility only)
				if storedCoopItems[k][1] ~= -1 then 	-- not an invalid character
					local curPosition = nil		-- stores the position the coop ghost will spawn

					-- select a position
					if shopKeeperPositions[2] ~= nil then	-- more than one position is available
						local ghostPosition = rng:RandomInt(#shopKeeperPositions) + 1
						curPosition = shopKeeperPositions[ghostPosition]
					else
						curPosition = shopKeeperPositions[1]
					end

					local coopGhosts = Isaac.Spawn(GhostShopMod.ENTITY_GS_COOP_GHOST, 0, 0, curPosition, Vector(0,0), nil):ToNPC()
					-- determine to which table the ghost belongs to
					if coopGhosts:GetData().HasTable == nil then
						coopGhosts:GetData().HasTable = k
					end
					--determine which player the items belonged to
					if coopGhosts:GetData().Identity == nil 
					and storedCoopItems[k][1] ~= nil then
						coopGhosts:GetData().Identity = storedCoopItems[k][1]
					end
					-- make it so that the player and his flies can't touch them
					local ghostFlag = EntityFlag.FLAG_NO_TARGET | EntityFlag.FLAG_NO_STATUS_EFFECTS
					coopGhosts:ClearEntityFlags(coopGhosts:GetEntityFlags())
					coopGhosts:AddEntityFlags(ghostFlag)
					coopGhosts.EntityCollisionClass = EntityCollisionClass.ENTCOLL_PLAYERONLY
					-- make them move like a player ghost
					coopGhosts:GetSprite():Play("Idle", true)
				end
			end
		end
	end
end


local function ghostShop_ReplaceGhost(entity, pathOne, pathTwo)
	local sprite = entity:GetSprite()

	sprite:ReplaceSpritesheet(0, pathOne)
	sprite:ReplaceSpritesheet(1, pathTwo)
	sprite:LoadGraphics()
end

local function ghostShop_ItemBlacklist(itemID)
	if itemID ~= 43			-- doesn't exist
	and itemID ~= 59		-- doesn't exist
	and itemID ~= 61		-- doesn't exist
	and itemID ~= 235		-- doesn't exist
	and itemID ~= 666		-- doesn't exist
	and itemID ~= 238		-- Key Piece 1
	and itemID ~= 239		-- Key Piece 2
	and itemID ~= 327		-- Polariod
	and itemID ~= 328		-- Negative
	and itemID ~= 550		-- Broken Shovel 1
	and itemID ~= 551		-- Broken Shovel 2
	and itemID ~= 552		-- Broken Shovel
	and itemID ~= 626		-- Knife Piece 1
	and itemID ~= 668 then		-- Dad's Note 
		return true
	else
		return false
	end
end

local function ghostShop_SaveHeldItems(itemID, i)
	local itemConfig = Isaac.GetItemConfig()

	-- first check which quality the item has
	if itemConfig:GetCollectible(itemID).Quality == 0 then
		table.insert(GameState.savedItems1,1, itemID)	-- insert and thus save the item into the quality 0 table
	elseif itemConfig:GetCollectible(itemID).Quality == 1 then
		table.insert(GameState.savedItems2,1, itemID)	-- insert and thus save the item into the quality 1 table
	elseif itemConfig:GetCollectible(itemID).Quality == 2 then
		table.insert(GameState.savedItems3,1, itemID)	-- insert and thus save the item into the quality 2 table
	elseif itemConfig:GetCollectible(itemID).Quality == 3 then
		table.insert(GameState.savedItems4,1, itemID)	-- insert and thus save the item into the quality 3 table
	elseif itemConfig:GetCollectible(itemID).Quality == 4 then
		table.insert(GameState.savedItems5,1, itemID)	-- insert and thus save the item into the quality 4 table
	end

	-- store the items from coop players again for the lil coop ghosts
	if i == 1 then		-- player 2
		table.insert(GameState.coopItems1, itemID)
	elseif i == 2 then	-- player 3
		table.insert(GameState.coopItems2, itemID)
	elseif i == 3 then	-- player 4
		table.insert(GameState.coopItems3, itemID)
	end
end

local function GetDimension(level)			-- function made by Wolfsauge
    local roomIndex = level:GetCurrentRoomIndex()

    for i = 0, 2 do
        if GetPtrHash(level:GetRoomByIdx(roomIndex, i)) == GetPtrHash(level:GetRoomByIdx(roomIndex, -1)) then
            return i
        end
    end
    
    return nil
end

function split(inputstr, sep)				-- function made by siraxtas
    if sep == nil then
        sep = "%s"
    end
    local t={}
    if string.match(inputstr, sep) then
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
        end
    else
        table.insert(t, inputstr)
    end
    return t
end

function GhostShop:onStart()
	-- GameState = json.decode(Isaac.LoadModData(GhostShop)) -- decodes the data from the savefile (returns a lua table)
	GameState = json.decode(GhostShop:LoadData()) -- decodes the data from the savefile (returns a lua table)
	-- print("Player")
	if GameState.seenItems == nil then GameState.seenItems = {} end					-- stores the id's from all items the players have seen during their run
 
	if GameState.savedItems1 == nil then GameState.savedItems1 = {} end				-- stores the id's of the current items the players have 
	if GameState.savedItems2 == nil then GameState.savedItems2 = {} end
	if GameState.savedItems3 == nil then GameState.savedItems3 = {} end
	if GameState.savedItems4 == nil then GameState.savedItems4 = {} end
	if GameState.savedItems5 == nil then GameState.savedItems5 = {} end

	if GameState.backUpItems1 == nil then GameState.backUpItems1 = {} end				-- stores the id's of the last set items the players had while winning, dying or exiting the game before starting a new run (only get filled at the start of a new run)
	if GameState.backUpItems2 == nil then GameState.backUpItems2 = {} end
	if GameState.backUpItems3 == nil then GameState.backUpItems3 = {} end
	if GameState.backUpItems4 == nil then GameState.backUpItems4 = {} end
	if GameState.backUpItems5 == nil then GameState.backUpItems5 = {} end

	if GameState.coopItems1 == nil then GameState.coopItems1 = {} end				-- stores the id's of the current items the coop players have (important for the item pool of the coop ghosts)
	if GameState.coopItems2 == nil then GameState.coopItems2 = {} end
	if GameState.coopItems3 == nil then GameState.coopItems3 = {} end

	if GameState.backUpCoopItems1 == nil then GameState.backUpCoopItems1 = {} end			-- stores the id's of the last set items the players had while winning, dying or exiting the game before starting a new run
	if GameState.backUpCoopItems2 == nil then GameState.backUpCoopItems2 = {} end
	if GameState.backUpCoopItems3 == nil then GameState.backUpCoopItems3 = {} end

	if GameState.preFlippedItems == nil then GameState.preFlippedItems = {} end			-- stores the id's from the default layout of the ghost shop
	if GameState.postFlippedItems == nil then GameState.postFlippedItems = {} end			-- stores the id's of the flipped layout (only get's filled once the player actually uses the Flip item (to prevent items from being removeed from the pool without the possibility to excess them)

	if GameState.prePrice == nil then GameState.prePrice = {} end					-- stores the current price for each of the individuell items of the default shop layout
	if GameState.postPrice == nil then GameState.postPrice = {} end					-- stores the current price for each of the individuell items of the flipped shop layout

	if GameState.preAddRestockPrice == nil then GameState.preAddRestockPrice = {} end		-- stores the current price for each of the individuell items of the default shop layout 
	if GameState.postAddRestockPrice == nil then GameState.postAddRestockPrice = {} end		-- stores the current price for each of the individuell items of the default shop layout
	
	if GameState.shoppingList == nil then GameState.shoppingList = {} end				-- stores which items the players bought in the last run
	if GameState.backupShoppingListOne == nil then GameState.backupShoppingListOne = {} end		-- stores which items have been bought twice in a row		(used to determine the price increase of the item)
	if GameState.backupShoppingListTwo == nil then GameState.backupShoppingListTwo = {} end		-- stores which items have been bought thrice or more in a row	(used to determine the price increase of the item)

	if GameState.backUpQuality == nil then GameState.backUpQuality = {} end				-- stores the determined quality of the default layout

	if GameState.backUpLayout == nil then GameState.backUpLayout = 0 end				-- stores which layout is currentlyused to spawn the items

	if GameState.deathBonus == nil then GameState.deathBonus = 0 end				-- stores the bonus the player gets from completing floors without dying (bonuses can increase the quality of the individuel shop slots)
	if GameState.winBonus == nil then GameState.winBonus = 0 end					-- stores the bonus the player gets from beating end game bosses (bonuses can increase the quality of the individuel shop slots)

end
GhostShop:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, GhostShop.onStart)

function GhostShop:onNewStart(bool)

	-- print("Game Start")
	
	if bool == false then		-- the start of a complete new game/run
		
		-- create a backup table. What this basically does is, it saves the items from the last run to be used in the current run [...]
		-- Should the player exit (and continue) the run then the last runs items are still saved while the main table could still [...]
		-- be updated in case the player chooses to start a new run (This way the json table can be updated on the fly)
		GameState.backupItems1 = GameState.savedItems1
		GameState.backupItems2 = GameState.savedItems2
		GameState.backupItems3 = GameState.savedItems3
		GameState.backupItems4 = GameState.savedItems4
		GameState.backupItems5 = GameState.savedItems5

		-- store the items from the json table in the regular table
		storedItems[1] = GameState.savedItems1
		storedItems[2] = GameState.savedItems2
		storedItems[3] = GameState.savedItems3
		storedItems[4] = GameState.savedItems4
		storedItems[5] = GameState.savedItems5

		-- do the same for the coop items
		GameState.backUpCoopItems1 = GameState.coopItems1
		GameState.backUpCoopItems2 = GameState.coopItems2
		GameState.backUpCoopItems3 = GameState.coopItems3

		storedCoopItems[1] = GameState.backUpCoopItems1
		storedCoopItems[2] = GameState.backUpCoopItems2
		storedCoopItems[3] = GameState.backUpCoopItems3

		-- reset which shop was entered
		NormalShopVisit = false
		GhostShopVisit = false

		-- ----------------------------------------------- -- 
		-- choose the new layout at the start of a new run --
		deathBonus = GameState.deathBonus		-- set up the bonuses
		winBonus = GameState.winBonus			
		luckyBonus = 0					-- depends on which layout will be used in the end

		-- get the rng
		local ghostRNG = RNG()
		ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

		-- choose which layout is going to be used (currently not mod friendly)
		local layoutRNG = (ghostRNG:RandomInt(100) + 1)
		if layoutRNG <= 5 then		-- unlucky layout
			usedLayout = 1
		elseif layoutRNG <= 35 then	-- normal layouts
			usedLayout = 2
		elseif layoutRNG <= 65 then	-- normal layouts
			usedLayout = 3
		elseif layoutRNG <= 96 then
			usedLayout = 4
		else				-- lucky layout
			usedLayout = 5
			luckyBonus = 4
		end
		
		-- first reset the quality table
		itemQuality = {}
		-- then get the quality of the items which will be available,
		-- but first get the slot which has always a quality 4 or lower item
		local maxQuality = false
		fixedQuality = ghostRNG:RandomInt(shopLayouts[usedLayout][1]) + 1	-- position depends on the set num of items set on the 1st position of the choosen layout

		for i = 1, shopLayouts[usedLayout][1] do 		-- the amount of times we do this depends on the num of item set in first position of the used shopLayout
					
			local qualityRange = (ghostRNG:RandomInt(25) + 1)	-- This allows the player to slightly affect the quality of the items down the line
			-- determine the quality
			if (qualityRange + deathBonus + winBonus + luckyBonus) <= 5 then
				-- the item quality will be 0
				table.insert(itemQuality,1)					-- (table, position, quality)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 5 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 10 then
				-- the item quality will be 1
				table.insert(itemQuality,2)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 10 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 15 then
				-- the item quality will be 2
				table.insert(itemQuality,3)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 15 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 20 then
				-- the item quality will be 3
				table.insert(itemQuality,4)
			elseif (qualityRange + deathBonus + winBonus) > 20 then
				-- the item quality will be 4
				table.insert(itemQuality,5)
				if usedLayout ~= 5 then
					maxQuality = true		-- should prevent the 'fixedQuality' to add another quality 5 slot
				end
			end
		end

		-- check if i is equal to the position in fixedQuality. This will be the guaranted slot
		for i = 1, shopLayouts[usedLayout][1] do
			if maxQuality == false
			and i == fixedQuality then
				itemQuality[i] = 5
			end
		end

		-- -------------------------------------------------- --
		-- keep track of the items the player bought last run -- 
		-- from the other two shopping table 
		ghostShop_checkShoppingList()

		-- ------------------------- --
		-- modded item compatibility --	
		ghostShop_ModCompatibility()
		ghostShop_ItemCompatibility(1)	

		-- ----------------------------- --
		-- reset the gamestate variables --
		GameState.deathBonus = 0		
		GameState.winBonus = 0
		GameState.preFlippedItems = {}		
		GameState.postFlippedItems = {}
		GameState.prePrice = {}		
		GameState.postPrice = {}
		GameState.preAddRestockPrice = {}		
		GameState.postAddRestockPrice = {}
		GameState.seenItems = {}

		-- -------------------------- --
		-- reset the normal variables --
		deathBonus = 0
		winBonus = 0
		flipped = 1
		preFlipped = {}
		postFlipped = {}
		prePrice = {}
		postPrice = {}
		seenCollectibles = {}

		-- reset the store sign position table
		storeSigns = {}
		storeSignsFlipped = {}

		-- reset the restock synergy
		preAddRestockPrice = {}
		postAddRestockPrice = {}
		for i = 1, shopLayouts[usedLayout][1] do 
			preAddRestockPrice[i] = 0
			postAddRestockPrice[i] = 0
		end

		hasWon = false
		openNomralShop = false
		shopStayOpen = false

		-- --------------------------- --
		-- reset all synergy variables --
		hasUsedDice = false	-- D6, Eternal D6, D Infinty and Dice Shard
		hasUsedD100 = false	-- extra for D100
		hasUsedD7 = false	-- D7
		hasUsedFlip = false	-- Flip
		flippedQuality = {}
		
		dontRestock = false
		needsToRestock = false
		hasSteamSale = false
		hasUsedFMN = false

	elseif bool == true then	-- the run continues
		-- note this might can be done in a way which only does this if the player can still get the ghost shop.
		-- update the regular item table with the backup table to know which items are left
		storedItems[1] = GameState.backupItems1
		storedItems[2] = GameState.backupItems2
		storedItems[3] = GameState.backupItems3
		storedItems[4] = GameState.backupItems4
		storedItems[5] = GameState.backupItems5

		-- update the tables for the coop ghosts
		storedCoopItems[1] = GameState.backUpCoopItems1
		storedCoopItems[2] = GameState.backUpCoopItems2
		storedCoopItems[3] = GameState.backUpCoopItems3

		-- ------------------------- --
		-- modded item compatibility --	
		ghostShop_ModCompatibility()

		-- ---------------------------------------- --
		-- restore the values of the shop variables -- 
		usedLayout = GameState.backUpLayout			-- make sure the layout and itemQualitye are still in place
		itemQuality = GameState.backUpQuality		

		-- make sure spawned items are tracked properly
		preFlipped = GameState.preFlippedItems		
		postFlipped = GameState.postFlippedItems
		-- also make sure to track which shop was visited or not
		if preFlipped[1] ~= nil then				
			if preFlipped[1] == -99 then 			-- means the player must have visited the normal shop
				NormalShopVisit = true
			else						-- means the player must have visited the ghost shop
				GhostShopVisit = true
			end
			-- print(NormalShopVisit)
			-- print(GhostShopVisit)
		end

		-- make sure the prices are tracked properly
		prePrice = GameState.prePrice		
		postPrice = GameState.postPrice
		preAddRestockPrice = GameState.preAddRestockPrice	
		postAddRestockPrice = GameState.postAddRestockPrice

		-- make sure that the flipped state is tracked properly.
		if preFlipped[(shopLayouts[usedLayout][1]) + 1] == -2 then	-- this checks the value for the flipped state which we added in the `Mod.onExit` function
			flipped = 1
		elseif preFlipped[(shopLayouts[usedLayout][1]) + 1] == -3 then
			flipped = 2
		end

		-- make sure to track the ghost signs properly (this checks which side the store was on)
		if flipped == 1 then
			if storeSigns[1] == nil then
				SpawnGhostSigns = true
			end
		elseif flipped == 2 then
			if storeSignsFlipped[1] == nil then
				SpawnGhostSigns = true
			end
		end

		-- ----------------------------------------------- --
		-- restore the values of the rest of the variables -- 
		shoppingList = GameState.shoppingList				-- make sure the shoplist ist tracked properly
		backupShoppingListOne = GameState.backupShoppingListOne
		backupShoppingListTwo = GameState.backupShoppingListTwo

		-- make sure the seen items are tracked properly
		seenCollectibles = GameState.seenItems

		-- win and death bonus
		deathBonus = GameState.deathBonus
		winBonus = GameState.winBonus
		-- make sure the game knows that the player beat an endgame boss
		if winBonus ~= 0 then
			hasWon = true
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, GhostShop.onNewStart)


function GhostShop:onShopItemPickup()
	local room = game:GetRoom()
	local roomType = room:GetType()
	local SaleCounter = 0			-- keeps track of the Steam Sale

	local itemConfig = Isaac.GetItemConfig()
			
	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true then

		-- ------------------------------------------ -- 
		-- Flip synergy
		if hasUsedFlip == true then
			-- get the rng
			local ghostRNG = RNG()
			ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

			if postFlipped[1] == nil then	-- it's the first time we flip the shop items	

				-- set up the values of the overarching variables. That way the postFlipped table gets trageted in the 'ghostShop_ChoseNewItem'-function
				usedFlipTable = postFlipped
				usedPriceTable = postPrice
				usedRestockTable = postAddRestockPrice

				for i = 1, shopLayouts[usedLayout][1] do	-- go through the amount of slots which should be there
					if preFlipped[i] ~= nil then			-- only do that if already items for the 'preFlipped'-layout are chosen
						local quality = 0

						-- first determine the quality
						if preFlipped[i] == -1 then	-- check if the table position contains a shop sign or not 
							-- because shop signs are seen as quality 0 the flipped quality is 4
							quality = 5 	-- = quality 4
						else
							-- for the rest we check the quality of the found item in the preFlipped table and determine it's quality 
							if itemConfig:GetCollectible(preFlipped[i]).Quality == 0 then
								quality = 5	-- quality 4
							elseif itemConfig:GetCollectible(preFlipped[i]).Quality == 1 then
								quality = 4
							elseif itemConfig:GetCollectible(preFlipped[i]).Quality == 2 then
								quality = 3
							elseif itemConfig:GetCollectible(preFlipped[i]).Quality == 3 then
								quality = 2
							elseif itemConfig:GetCollectible(preFlipped[i]).Quality == 4 then
								quality = 1	-- quality 0
							end
						end
						-- chose an item for the postFlipped table	
						ghostShop_ChoseNewItem(ghostRNG, quality, i, 0, 0, 1, 0, 0, 0)		
						-- ghostShop_ChoseNewItem(rng, quality, roll, entity placeholder, spawnSign = false , addPrice = true, restock = false, reroll = false, spawnItem = false)
					end
				-- firstFlipp = false
				end
			end
			-- first look for all the signs in the slots and remove them all
			for _, entity in pairs(Isaac.GetRoomEntities()) do		
				if entity.Type == EntityType.ENTITY_EFFECT then
					if entity.Variant == EffectVariant.GHOST_STORE_SIGN 
					or entity.Variant == EffectVariant.FLIP_EFFECT then
						entity:Remove()
					end
				end
			end
			for i = 1, shopLayouts[usedLayout][1] do	-- go through the amount of slots which should be there
				if shopLayouts[usedLayout][i + 1] ~= nil then
					local itemFound = false		-- keeps track if the next loop found an shop item in it's place
					-- find items which are in the place of the slots
					for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
						-- make sure it's a Shop Item
						if entity:ToPickup():IsShopItem() then
							-- flip the item!
							ghostShop_FlipLayouts(ghostRNG, entity, i)
							-- let the game know that an item was found on the spot
							itemFound = true
						end
					end
					if itemFound == false then	-- no item has been found so a new one or a shop sign has to be spawned
						local sign = -1		-- variable used in the function for the Flip synergy. Normally it would carry the id number of an item, but here it value used for the shop sign
						-- flip the item!			
						ghostShop_FlipLayouts(ghostRNG, sign, i)
					end
				end
			end
			hasUsedFlip = false
			-- restock synergy
			dontRestock = false
		end	

		-- D6, Eternal D6 and D Infinty synergy
		if hasUsedDice == true	then		-- one of the players used on of the dice mentions above

			local restockTable = {}		-- table which keeps track if a slot is empty(2), has a shoh sign(-1) or contains a shop item(1)	-- table which keeps track if Flip was used. (preAddRestockPrice) for the regular layout, (postAddRestockPrice) for the flipped layout
			
			-- get the rng
			local ghostRNG = RNG()
			ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)
					
			-- get the table we are looknig through
			if flipped == 1 then		-- it's the normal Layout
				usedFlipTable = preFlipped
				usedPriceTable = prePrice
				usedRestockTable = preAddRestockPrice
				usedShopSignTable = storeSigns
			elseif flipped == 2 then	-- it's the flipped Layout
				usedFlipTable = postFlipped
				usedPriceTable = postPrice
				usedRestockTable = postAddRestockPrice
				usedShopSignTable = storeSignsFlipped
			end

			for i = 1, shopLayouts[usedLayout][1] do
				if shopLayouts[usedLayout][i + 1] ~= nil then
					-- find items which are in the place of the slots
					for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
						-- make sure it's a Shop Item
						if entity:ToPickup():IsShopItem() then
							local items = entity
							local quality = (itemQuality[i])	-- picks the quality from the corresponding position of the quality table

							-- chose a new item to which the old one gets morphed "rerolled" into
							ghostShop_ChoseNewItem(ghostRNG, quality, i, items, 1, 1, 0, 1, 0)		
							-- ghostShop_ChoseNewItem(rng, quality, roll, entity, spawnSign = true , addPrice = true, restock = false, reroll = true, spawnItem = false)
						end
					end
				end
			end
			-- spawn the items which are not shop items again
			for j = 1, #rerollTable do

				-- determine the quality of the quality of the item in question
				if itemConfig:GetCollectible(rerollTable[j]).Quality == 0 then
					quality = 1	-- quality 0
				elseif itemConfig:GetCollectible(rerollTable[j]).Quality == 1 then
					quality = 2
				elseif itemConfig:GetCollectible(rerollTable[j]).Quality == 2 then
					quality = 3
				elseif itemConfig:GetCollectible(rerollTable[j]).Quality == 3 then
					quality = 4
				elseif itemConfig:GetCollectible(rerollTable[j]).Quality == 4 then
					quality = 5	-- quality 4
				end
				searchedPosition = rerollPosition[j]
				
				-- chose a new item to which the old one gets morphed "rerolled" into
				ghostShop_ChoseNewItem(ghostRNG, quality, 1, 1, 0, 0, 0, 2, 0)		
				-- ghostShop_ChoseNewItem(rng, quality, roll placeholder, entity placeholder, spawnSign = false , addPrice = false, restock = false, reroll = true, spawnItem = false)
			end
			rerollTable = {}
			rerollPosition = {}
			searchedPosition = nil
			hasUsedDice = false
			-- restock synergy
			dontRestock = false
		end

		-- D7 synergy
		if hasUsedD7 == true then
			hasUsedD7 = false
		end

		-- check if one of the players used the Mystery Gift item
		if hasUsedMyGi[3] ~= nil then
			-- we look for an item on the position stored in 'hasUsedMyGi[3]'
			for _, entity in pairs(Isaac.FindInRadius(hasUsedMyGi[3], 2, EntityPartition.PICKUP)) do
				if entity:ToPickup().Variant == PickupVariant.PICKUP_COLLECTIBLE then
					-- change the item
					local quality = hasUsedMyGi[2]

					-- get the rng
					local ghostRNG = RNG()
					ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

					-- chose a new item to which the old one gets morphed (not rerolled!) to
					ghostShop_ChoseNewItem(ghostRNG, quality, 1, entity, 0, 0, 0, 0, 0)		
					-- ghostShop_ChoseNewItem(rng, quality, roll placeholder, entity, spawnSign = false , addPrice = false, restock = false, reroll = false, spawnItem = false)
				end
			end
			-- reset Mystery Gift
			hasUsedMyGi = {false}
		end

		-- if the player restarts/reloads the game make sure that shop signs are spawned in the empty shop slots
		local itemPosition = {}
		if SpawnGhostSigns == true 
		and room:IsMirrorWorld() == true
		and GhostShopVisit == true 
		and NormalShopVisit == false then
			local player = Isaac.GetPlayer(0)
			for i = 1, shopLayouts[usedLayout][1] do
				if shopLayouts[usedLayout][i + 1] ~= nil then
					local removed = false
					local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, shopLayouts[usedLayout][i + 1], Vector(0,0), nil):ToEffect()
					for _, items in pairs(Isaac.FindInRadius(shopSign.Position, 16, EntityPartition.PICKUP)) do
						if items:ToPickup():IsShopItem() then
							if items.Variant == PickupVariant.PICKUP_COLLECTIBLE then
								shopSign:Remove()
								removed = true
							end
						else
							shopSign:Remove()
							removed = true
						end
					end
					if removed == false then
						-- save the position of the sign
						if flipped == 1 then		-- it's the normal Layout
							table.insert(storeSigns,1,shopSign.Position)
						elseif flipped == 2 then	-- it's the flipped Layout
							table.insert(storeSignsFlipped,1,shopSign.Position)
						end
					end
				end
			end
			SpawnGhostSigns = false
		end

		-- -------------------------- --
		-- look for a Restock Machine --
		for _, entities in pairs(Isaac.GetRoomEntities()) do
			if entities.Type == EntityType.ENTITY_SLOT then
				
				-- check for the right slot variant
				if entities.Variant == 10 then	-- reroll maschine
					local data = entities:GetData()
					local sprite = entities:GetSprite()

					-- check if the slot was just spawned
					if data.InitMachine == nil then
						data.InitMachine = true
						
						-- replace spritesheet and animation
						sprite:Load("gfx/ghostshop_restockmachine.anm2", true)
						sprite:ReplaceSpritesheet(0, "gfx/items/slots/custom/slot_ghostshop_out_of_stock.png")
						sprite:LoadGraphics()

					end
					-- update it's idle animation once it is initiated
					if data.InitMachine == true then
						if data.ChooseIdleAnim == nil then
							data.ChooseIdleAnim = true

							local roll = math.random(1,6)
							if roll == 1 then
								sprite:Play("Idle")
							elseif roll == 2 then
								sprite:Play("Idle2")
							elseif roll == 3 then
								sprite:Play("Idle3")
							elseif roll == 4 then
								sprite:Play("Idle4")
							elseif roll == 5 then
								sprite:Play("Idle5")
							else
								sprite:Play("Idle6", true)
							end
						end

						if data.ChooseIdleAnim == true then

							if sprite:IsFinished("Idle") then
								sprite:Play("Idle2", true)
							elseif sprite:IsFinished("Idle2") then
								sprite:Play("Idle3", true)
							elseif sprite:IsFinished("Idle3") then
								sprite:Play("Idle4", true)
							elseif sprite:IsFinished("Idle4") then		-- end of the cicle. After that it goes back to the first idle animation
								sprite:Play("Idle", true)
							elseif sprite:IsFinished("Idle5") then		-- when choosen it only play once and then the idle animation goes back to the regular cicle
								sprite:Play("Idle", true)
							end
						end

						-- make it intengable to other entities
						entities.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
					end
				end
			end
		end


		-- ------------------------------------------------ --
		-- stuff the player character has to be checked for -- 
		for i = 0, (game:GetNumPlayers() - 1) do
			local player = Isaac.GetPlayer(i)
			local playerData = player:GetData()

			-- once an item is found that the player could have touched we check if an item is still in the radius of a shop sign.. if so the player didn't bought it
			if currentItemPosition[1] ~= nil 	-- player walked over a shop item and saved the position
			and player:IsHoldingItem() then		-- is holding something up
				local removed = false
				local radius = 16	-- the radius in which the loop search for pickups

				-- spawn the shop sign on the item position
				local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, currentItemPosition[1], Vector(0,0), nil):ToEffect()

				-- now we look if there's still an item on the shop sign position
				for _, items in pairs(Isaac.FindInRadius(shopSign.Position, radius, EntityPartition.PICKUP)) do
					-- if so we remove it again
					if items:ToPickup():IsShopItem() then
						if items.Variant == PickupVariant.PICKUP_COLLECTIBLE then	-- there's still an item the

							shopSign:Remove()	-- so the shop sign has to be removed
							removed = true
						else
							shopSign:Remove()
							removed = true
						end
					else
						shopSign:Remove()
						removed = true	
					end
				end
				if removed == false then		-- there's no item anymore

					-- but first it has to be checked which layout table should be used at the shop sign position has to be saved in the according table
					if flipped == 1 then		-- it's the normal Layout
						table.insert(storeSigns,1,shopSign.Position)	-- store the position of the shop sign
						usedFlipTable = preFlipped
						usedPriceTable = prePrice
					elseif flipped == 2 then	-- it's the flipped Layout
						table.insert(storeSignsFlipped,1,shopSign.Position)	-- store the position of the shop sign
						usedFlipTable = postFlipped
						usedPriceTable = postPrice
					end

					-- now we need to update the pre-/postflipped table to make sure Flip doesn't spawn old items
					-- first go through all layout positions
					for i = 1, shopLayouts[usedLayout][1] do
						if shopLayouts[usedLayout][i + 1] ~= nil then
							if usedFlipTable[i] ~= -1 then
								local updateFlipTable = true
								for _, items in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 6, EntityPartition.PICKUP)) do
									if items:ToPickup():IsShopItem() then
										if items.Variant == PickupVariant.PICKUP_COLLECTIBLE then	-- there's still an item there
											-- then check if the item which is still on this position matches with one from the pre-/postflipped table
											updateFlipTable = false		-- there's still an item on this position of the table so we don't need to update the flip table on this position
										end
									end	
								end
								-- check if the pre-/postflipped table should be updated on this position
								if updateFlipTable == true then		-- if it is still true, then no item has been found in the loop above

									-- insert the item id in the shopping list
									table.insert(shoppingList,1,usedFlipTable[i])

									-- update the flipped table
									usedFlipTable[i] = -1				-- updated it so that there's now the value of a shop sign in the table
									-- add a placeholder price on this postion
									usedPriceTable[i] = -99
								end
							end
						end
					end
					-- give the sign a chance to be possessed by a little ghost
					if shopSign:GetData().IsPossessed == nil then
						local roll = math.random(1,8)			-- only has a 12,5% chance to be possessed
						if roll == 1 then				-- a possessed sign should be spawned
							shopSign:GetData().IsPossessed = true	-- this is now the home of a little ghost
							numLittleGhosts = numLittleGhosts + 1	-- adjust the number of little ghost which should be spawned on revisting the shop
							-- needs a set up for a different animation
						end
					end
				end
				currentItemPosition = {}
			end

			if player:IsCoopGhost() == false
			and player:HasCollectible(CollectibleType.COLLECTIBLE_RESTOCK) then
				-- Restock synergy
				if needsToRestock == true then		-- a new shop pickup was spawned and replaced with a restock sign
					local restockTable = {}		-- table which keeps track if a slot is empty(2), has a shoh sign(-1) or contains a shop item(1)

					-- get the rng
					local ghostRNG = RNG()
					ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)
					
					-- get the table we are looknig through
					if flipped == 1 then		-- it's the normal Layout
						usedFlipTable = preFlipped
						usedPriceTable = prePrice
						usedRestockTable = preAddRestockPrice
					elseif flipped == 2 then	-- it's the flipped Layout
						usedFlipTable = postFlipped
						usedPriceTable = postPrice
						usedRestockTable = postAddRestockPrice
					end

					-- now that there's an empty slot we check where that empty slot is
					for i = 1, shopLayouts[usedLayout][1] do
						local noEmptySlot = false
						if shopLayouts[usedLayout][i + 1] ~= nil then 	-- it's a valid slot
							-- print(usedFlipTable[i])
							if usedFlipTable[i] == -1 then		-- the slot contains a shop/store sign
								table.insert(restockTable,-1)	
								noEmptySlot = true
							else
								-- we look if we can find an item in this slot. Originally it should have had one
								for _, entities in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 16, EntityPartition.PICKUP)) do
									if entities:ToPickup():IsShopItem() then
										table.insert(restockTable,1)	
										noEmptySlot = true
									end
								end
							end
							-- now check if neither a shop sign nor item was found
							if noEmptySlot == false then	-- it's still false
								table.insert(restockTable,2)
							end
						end
					end
					-- make sure that restockTable isn't empty anymore
					if restockTable[1] ~= nil then
						local quality = 0		-- keeps track of the determined quality of the items
						-- then we go through the restockTable and find the empty(2) slot again
						for j = 1, shopLayouts[usedLayout][1] do

							if restockTable[j] == 2 	-- it's empty
							and usedFlipTable[j] ~= nil then

								-- check the quality of the found item in the preFlipped table and determine it's quality 
								if itemConfig:GetCollectible(usedFlipTable[j]).Quality == 0 then
									quality = 1	-- quality 0
								elseif itemConfig:GetCollectible(usedFlipTable[j]).Quality == 1 then
									quality = 2
								elseif itemConfig:GetCollectible(usedFlipTable[j]).Quality == 2 then
									quality = 3
								elseif itemConfig:GetCollectible(usedFlipTable[j]).Quality == 3 then
									quality = 4
								elseif itemConfig:GetCollectible(usedFlipTable[j]).Quality == 4 then
									quality = 5	-- quality 4
								end

								-- increase the Restock counter for this position
								usedRestockTable[j] = usedRestockTable[j] + 1

								-- ---------------------------------------------------------------------------------------------------------------

								if shopLayouts[usedLayout][j + 1] ~= nil then	-- prevents a small bug from happpening. Somehow sometimes there's one more position than there should. Idk what causes this

									-- chose a new item which replaces the bought one
									ghostShop_ChoseNewItem(ghostRNG, quality, j, 0, 1, 1, 1, 0, 1)		
									-- ghostShop_ChoseNewItem(rng, quality, roll, entity placeholder, spawnSign = true , addPrice = true, restock = true, reroll = false, spawnItem = true)
								end
							end
						end
					end
					needsToRestock = false
				end
			else
				-- check for shop items in the close area of the player
				for _, entity in pairs(Isaac.GetRoomEntities()) do
					if entity.Type == EntityType.ENTITY_PICKUP
					and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE 
					and entity:ToPickup():IsShopItem() then

						local items = entity
						-- if not player:GetNumCoins() < items:ToPickup().Price
						if (player.Position - items.Position):Length() < player.Size + items.Size then
							-- print("begin")
							local itemId = items.SubType 	-- :ToPickup().SubType
							local checkfurther = false
							if currentItemPosition[1] == nil
							or items.Position ~= currentItemPosition[1] then
								currentItemPosition = {}
								table.insert(currentItemPosition,items.Position)
								-- try to store the item id somewhere
							end
						end
					end
				end
			end

			-- Glitched Crown synergy
			if player:IsCoopGhost() == false then

				if player:HasCollectible(CollectibleType.COLLECTIBLE_GLITCHED_CROWN)
				or player:GetPlayerType() == 21 then

					-- check which side the player is currently on
					if flipped == 1 then
						usedRestockTable = preAddRestockPrice
						usedPriceTable = prePrice
					elseif flipped == 2 then
						usedRestockTable = postAddRestockPrice
						usedPriceTable = postPrice
					end

					-- apply the Steam Sale effect to the shop items
					for i = 1, shopLayouts[usedLayout][1] do			-- counts through 1, 2, 3, 4....
						if shopLayouts[usedLayout][i + 1] ~= nil then	-- go through all the shop item positions
							-- find items which are in the place of the slots
							for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
								-- make sure it's a Shop Item
								if entity:ToPickup():IsShopItem() then
									local shopItem = entity
									if hasSteamSale == true then
										-- adjust the price
										shopItem:ToPickup().AutoUpdatePrice = false
										shopItem:ToPickup().Price = (7 + (usedRestockTable[i]))
									else
										-- adjust the price
										shopItem:ToPickup().AutoUpdatePrice = false
										shopItem:ToPickup().Price = (15 + (usedRestockTable[i] * 2))
									end
								end
							end
						end
					end
				end
			end

			-- Steam Sale synergy
			if player:IsCoopGhost() == false
			and player:HasCollectible(CollectibleType.COLLECTIBLE_STEAM_SALE) then
				if hasSteamSale == false then
					hasSteamSale = true

					-- check which side the player is currently on
					if flipped == 1 then
						usedPriceTable = prePrice
					elseif flipped == 2 then
						usedPriceTable = postPrice
					end

					-- apply the Steam Sale effect to the shop items
					for i = 1, shopLayouts[usedLayout][1] do			-- counts through 1, 2, 3, 4....
						if shopLayouts[usedLayout][i + 1] ~= nil then	-- go through all the shop item positions
							-- find items which are in the place of the slots
							for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
								-- make sure it's a Shop Item
								if entity:ToPickup():IsShopItem() then
									local shopItem = entity
									-- then apply the Steam Sale effect
									shopItem:ToPickup().AutoUpdatePrice = false
									shopItem:ToPickup().Price = (math.floor(usedPriceTable[i] / 2))
								end
							end
						end
					end
				end
				SaleCounter = SaleCounter + 1
			end
		end
		-- check if the SaleCounter is still 0
		if SaleCounter == 0 			-- means none of the players has a Steam Sale anymore
		and hasSteamSale == true then 		-- but had they had one in the past
			hasSteamSale = false		-- reset hasSteamSale 

			-- check which side the player is currently on
			if flipped == 1 then
				usedPriceTable = prePrice
			elseif flipped == 2 then
				usedPriceTable = postPrice
			end

			-- reapply the base price to the shop items
			for i = 1, shopLayouts[usedLayout][1] do			-- counts through 1, 2, 3, 4....
				if shopLayouts[usedLayout][i + 1] ~= nil then	-- go through all the shop item positions
					-- find items which are in the place of the slots
					for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
						-- make sure it's a Shop Item
						if entity:ToPickup():IsShopItem() then
							local shopItem = entity
							-- then apply the normal price
							shopItem:ToPickup().AutoUpdatePrice = false
							shopItem:ToPickup().Price = usedPriceTable[i]
						end
					end
				end
			end
		end
	end

	-- ------------------------------------------ --
	-- other stuff on the other side of the floor -- 
	if openNomralShop == true		-- we found a shop we would like to open
	and room:IsClear() then			-- And no enemies are in the room anymore 
		
		-- look again for the shop door
		for i = 0, 7 do
			local GridEntityDoor = room:GetDoor(i)
			if GridEntityDoor then
				GridEntityDoor = GridEntityDoor:ToDoor()
				if GridEntityDoor:IsRoomType(RoomType.ROOM_SHOP) then
					
					GridEntityDoor.State = DoorState.STATE_OPEN
					GridEntityDoor:GetSprite():Play("Open")
					shopStayOpen = true
				end
			end
		end
		openNomralShop = false	-- reset the variable again. That way it only get called once per room
	end
	if shopStayOpen == true	then	-- the shop already began to play the opening animation
		-- look again for the shop door
		for i = 0, 7 do
			local GridEntityDoor = room:GetDoor(i)
			if GridEntityDoor then
				GridEntityDoor = GridEntityDoor:ToDoor()
				if GridEntityDoor:IsRoomType(RoomType.ROOM_SHOP) then
					
					if GridEntityDoor:GetSprite():IsFinished("Open") then
						GridEntityDoor:GetSprite():Play("Opened", true)
					end
				end
			end
		end
		shopStayOpen = false
	end 
end
GhostShop:AddCallback(ModCallbacks.MC_POST_UPDATE, GhostShop.onShopItemPickup)

-- ----------------- --
-- shop layout spawn --
-- ----------------- --
function GhostShop:onShopEnter()
	local player = Isaac.GetPlayer(0)

	local level = game:GetLevel()
	local stage = level:GetStage()
	local stageType = level:GetStageType()

	local room = game:GetRoom()
	local roomType = room:GetType()

	-- check if the player is in a shop in Downpour II
	if roomType == RoomType.ROOM_SHOP 
	and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
	and stage == LevelStage.STAGE1_2 then

		-- restock synergy
		dontRestock = true

		-- check if the player visits the normal shop after the Mirror shop
		if room:IsMirrorWorld() ~= true
		and GhostShopVisit == true then
			-- check the room for shop items
			for _, entity in pairs(Isaac.GetRoomEntities()) do
				if entity.Type == EntityType.ENTITY_PICKUP 
				and entity:ToPickup():IsShopItem() then
					-- remove the item
					entity:Remove()
				end
			end
			
		end

		if room:IsFirstVisit() == true then		-- first time visting a shop on this floor
			-- check the room for shop items
			if GhostShopVisit == false then 	-- should make sure that this gets only checked if the player hasn't vivisted ghost shop yet
				 for _, entity in pairs(Isaac.GetRoomEntities()) do
			  		if entity.Type == EntityType.ENTITY_PICKUP 
			 		and entity:ToPickup():IsShopItem() then
			 			-- if a shop item is found set NormalShopVisit to 'true' since it must be the normal shop of the level
						NormalShopVisit = true		-- prevents the shop item to be spawned
						-- fill the preFlipp table so we can keep track of the visit shop in case the player quited the game completly
						preFlipped[1] = -99
					end
				end
			end

			if NormalShopVisit == false then 	-- must be the other shop
				GhostShopVisit = true
			end

			-- check if the GhostShopVisit is true now
			if room:IsMirrorWorld() == true
			and GhostShopVisit == true
			and NormalShopVisit == false then

				-- get the rng
				local ghostRNG = RNG()
				ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

				-- Steam Sale Synergy
				for i = 0, (game:GetNumPlayers() - 1) do
					local player = Isaac.GetPlayer(i)
					local playerData = player:GetData()

					if player:IsCoopGhost() == false
					and player:HasCollectible(CollectibleType.COLLECTIBLE_STEAM_SALE) then
						hasSteamSale = true
					end
				end

				-- spawn the room layout:
				for position, quality in pairs(itemQuality) do 		-- get the quality and position of each item in the table. 
					-- position = equal to the position in the shopLayout table + 1...
					--	      Used to determine the table position of the vector we need.
					-- quality =  equal to the table used from storedItems...
					--	      Used to determine which quality table will be used to spawn an item

					-- set up the values of the overarching variables. That way the postFlipped table gets trageted in the 'ghostShop_ChoseNewItem'-function
					usedFlipTable = preFlipped
					usedPriceTable = prePrice
					usedRestockTable = preAddRestockPrice

					if hasUsedFMN == false then	-- if the player hasn't used the 'Forget Me Now' or 'Glowing Hourglass' item.
						-- ----------------------------------------------------------------- --

						if shopLayouts[usedLayout][position + 1] ~= nil then	-- prevents a small bug from happpening. Somehow sometimes there's one more position than there should. Idk what causes this
							-- chose the items for the preFlipped table	
							ghostShop_ChoseNewItem(ghostRNG, quality, position, 0, 1, 1, 0, 0, 1)	
							-- ghostShop_ChoseNewItem(rng, quality, roll, entity placeholder, spawnSign = true, addPrice = true, restock = false, reroll = false, spawnItem = true)
						end
						-- ----------------------------------------------------------------- --
					else	-- we have to spawn the existing layout. 
						
						if shopLayouts[usedLayout][position + 1] ~= nil then
							if preFlipped[position] == -1 then 	-- we need to spawn a shop sign
								local shopSign = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.GHOST_STORE_SIGN, 0, shopLayouts[usedLayout][position + 1], Vector(0,0), nil):ToEffect()

							elseif preFlipped[position] > 0 then				-- we need to spawn the item from that position
								local shopItem = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, preFlipped[position], shopLayouts[usedLayout][position + 1], Vector(0,0), nil) -- :ToPickup()
								shopItem:ToPickup().AutoUpdatePrice = false
								shopItem:ToPickup().Price = usedPriceTable[position]
							end
						end
					end
				end
				-- haunted chest position
				if usedLayout == 5 then		-- / unlucky layout
					local hauntedChest = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_HAUNTEDCHEST, ChestSubType.CHEST_CLOSED, Vector(85,170), Vector(0,0), nil)

				elseif usedLayout == 4 or usedLayout == 3 or usedLayout == 2 then
					local chestChance = ghostRNG:RandomInt(2) + 1
					if chestChance == 1 then
						local hauntedChest = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_HAUNTEDCHEST, ChestSubType.CHEST_CLOSED, Vector(85,170), Vector(0,0), nil)
					end
				end
				-- spawn the coop ghost 
				if storedCoopItems[1][1] ~= nil then	-- there was at least a second player
					-- get the rng
					local ghostRNG = RNG()
					ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

					ghostShop_SpawnCoopGhost(ghostRNG)
				end
				hasUsedFMN = false	-- reset the Forget Me Now use
			end

		-- spawn the shop signs once the player enters the shop again --
		else
			if room:IsMirrorWorld() == true
			and GhostShopVisit == true 
			and NormalShopVisit == false then
				local newNumLittleGhosts = 0
				-- print(storeSigns[1])
				for i = 1, shopLayouts[usedLayout][1] do
					if shopLayouts[usedLayout][i + 1] ~= nil then
						-- check for the flipped layouts
						local layoutOne = nil
						local layoutTwo = nil

						if flipped == 1 then		-- it's the normal Layout
							layoutOne = preFlipped
							layoutTwo = postFlipped
						elseif flipped == 2 then	-- it's the flipped Layout
							layoutOne = postFlipped
							layoutTwo = preFlipped
						end
							
						if layoutOne[i] == -1 then
								ghostShop_SpawnGhostSign(shopLayouts[usedLayout][i + 1], 3)
						end
						if postFlipped[1] ~= nil then		-- the layout has been flipped before
							local hasFlipped = false

							for i = 0, (game:GetNumPlayers() - 1) do
								local player = Isaac.GetPlayer(i)
								local playerData = player:GetData()

								if player:IsCoopGhost() == false
								and player:HasCollectible(CollectibleType.COLLECTIBLE_FLIP) then
									hasFlipped = true
								end
							end
							if hasFlipped == true then	-- one of the players has the flip item
								-- look through the postFlipped table to see if the flip effect should be a shop sign or a questionmark
								if layoutTwo[i] == -1 then	-- contains a shop sign
									local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, shopLayouts[usedLayout][i + 1], Vector(0,0),nil):ToEffect()
									flipEffect:GetSprite():Play("Sign", true)
									flipEffect.Position = Vector((flipEffect.Position.X) + 12, (flipEffect.Position.Y) - 17)
								elseif layoutTwo[i] > 0 then	-- contains an item
									local flipEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FLIP_EFFECT, 0, shopLayouts[usedLayout][i + 1], Vector(0,0),nil):ToEffect()
									flipEffect:GetSprite():Play("Questionmark", true)
									flipEffect.Position = Vector((flipEffect.Position.X) + 12, (flipEffect.Position.Y) - 17)
								end
							end
						end
					end
				end
				-- spawn the coop ghost on reentering the room
				if storedCoopItems[1][1] ~= nil then	-- there was at least a second player
					-- get the rng
					local ghostRNG = RNG()
					ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

					ghostShop_SpawnCoopGhost(ghostRNG)
				end
			end
		end
		-- restock synergy
		dontRestock = false
	end

	-- -------------------------------------------------------------------------------- --
	-- if the player visted the ghost shop make that the door of the normal shop opens. --
	-- That should give player a clue that something changed
	if (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
	and stage == LevelStage.STAGE1_2
	and room:IsMirrorWorld() ~= true
	and GhostShopVisit == true 
	and roomType ~= RoomType.ROOM_SHOP 		-- this and the next line prevent the Secret room to open without bombing the wall
	and roomType ~= RoomType.ROOM_SECRET then
		
		-- look for the shop door
		for j = 0, 7 do
			local GridEntityDoor = room:GetDoor(j)
			if GridEntityDoor then
				GridEntityDoor = GridEntityDoor:ToDoor()
				if GridEntityDoor:IsRoomType(RoomType.ROOM_SHOP) then
					openNomralShop = true 	-- gets called again in the 'update' callback. Only triggers once in none hostile rooms 
					GridEntityDoor:GetSprite():Play("Closed")
				end
			end
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, GhostShop.onShopEnter)

-- ----------------------------------------- --
-- Floor/Death bonus & Mine Chase/Coop stuff --
-- ----------------------------------------- --
function GhostShop:onNewFloor(_)
	local itemConfig = Isaac.GetItemConfig()
	local level = game:GetLevel()
	local stage = level:GetStage()
	local stageType = level:GetStageType()

	-- ------------------------------------------------------------------- --
	-- only increased the floor bonus counter if the player hasn't won yet --
	if hasWon == false then
		deathBonus = deathBonus + 1
	end

	-- ------------------------------------------ --
	-- prevent the shop from other floors to open --
	openNomralShop = false

	-- ------------------------------------------ --
	-- temporary store the items the players have --
	-- sadly unavoidable in case of coop babies or death in the mine chase sequence
	if game:GetNumPlayers() > 1 then	-- stuff which we do if there are more than 1 player aka coop happens
		for i = 0, (game:GetNumPlayers() - 1) do
			local player = Isaac.GetPlayer(i)
			local coopTable = (i + 1)		-- for coop player tables

			if player:IsCoopGhost() == false then	-- player is still alive.. in a way
				-- go through all normal items (not optimal I know...)
				-- reset the table we draw later from
				if temporaryStored[coopTable][1] ~= nil then	-- there's an item in the table slot!
					temporaryStored[coopTable] = {}
				end
				for j = 1, numCollectibles do
				
					if Isaac.GetItemConfig():GetCollectible(j) ~= nil
					and player:HasCollectible(j) then
				
						if ghostShop_ItemBlacklist(j) == true then	-- ghostShop_ItemBlacklist(ID of the item)

							-- insert the item in the temporary table
							if temporaryStored[coopTable] ~= nil then
								table.insert(temporaryStored[coopTable],1, j)
							end
						end
					end
				end	
			end
		end
	else					-- stuff we do normaly
		local player = Isaac.GetPlayer(0)	-- as no coop is happening we just need to get one player
		-- check if the player is in the Mines or Ashpit
		if (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
		and stage == LevelStage.STAGE2_2
		and player:HasCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_1) then	-- Mother chase only spawns when you have knife piece 1
			-- go through all normal items
			for j = 1, numCollectibles do

				if Isaac.GetItemConfig():GetCollectible(j) ~= nil
				and player:IsCoopGhost() == false
				and player:HasCollectible(j) then
					
					if ghostShop_ItemBlacklist(j) == true then	-- ghostShop_ItemBlacklist(ID of the item)

						-- insert the item in the temporary table
						table.insert(temporaryStored[1],1, j)
					end
				end
			end
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, GhostShop.onNewFloor)

function GhostShop:onEndBossKill(entity)
	local data = entity:GetData()
	local motherKill = false

	if entity:IsDead() -- is it dead?
	and data.Died == nil then -- did it already die
		data.Died = true -- well now it is dead	
		-- check which boss was killed	
		if entity.Type == EntityType.ENTITY_THE_LAMB then
			winBonus = 7
		elseif entity.Type == EntityType.ENTITY_ISAAC and entity.Variant == 1 then			-- blue baby
			if hasWon == false then	-- hasn't killed Hush
				winBonus = 5
			end
		elseif entity.Type == EntityType.ENTITY_MEGA_SATAN_2 then
			winBonus = 12
		elseif entity.Type == EntityType.ENTITY_HUSH then
			winBonus = 15
		elseif entity.Type == EntityType.ENTITY_DELIRIUM then
			winBonus = 20
		elseif entity.Type == EntityType.ENTITY_MOTHER then
			if entity.Variant == 10 then
				winBonus = 20		
			else
				motherKill = true
			end
		elseif entity.Type == EntityType.ENTITY_DOGMA then
			winBonus = 15
		elseif entity.Type == EntityType.ENTITY_BEAST then
			winBonus = 20
		end
		
		if motherKill == false then		-- prevents the first phase of mother to nullify the death bonus
			deathBonus = 1 	-- prevents the death bonus to be negative
			hasWon = true
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_THE_LAMB)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_ISAAC)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_MEGA_SATAN_2)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_HUSH)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_DELIRIUM)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_MOTHER)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_DOGMA)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_BEAST)


-- ------------------------ --
-- Restock & item synergies --
-- ------------------------ --
function GhostShop:onCollectibleSpawn(pickup)
	local room = game:GetRoom()
	local roomType = room:GetType()
	
	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and dontRestock == false then
		
		if pickup:ToPickup():IsShopItem() then		-- it's a new shopitem!
			local hasRestock = false
			-- check if the player has Restock!
			for i = 0, (game:GetNumPlayers() - 1) do
				local player = Isaac.GetPlayer(i)
				if player:IsCoopGhost() == false then
					if player:HasCollectible(CollectibleType.COLLECTIBLE_RESTOCK) then
						hasRestock = true
					end
					-- glitched crown placeholder
				end
			end

			if hasRestock == true 
			or hasUsedD7 == true then
				-- remove the new shopitem!
				pickup:Remove()
				needsToRestock = true
			end
		end
	end
	-- keep track of the items spawned
	if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
		if hasUsedMyGi[1] == true 
		and pickup.SubTYpe ~= CollectibleType.COLLECTIBLE_POOP then
			-- insert the items position in the second position of the table	
			hasUsedMyGi[3] = pickup.Position

			-- reset 'hasUsedMyGi[1]'
			hasUsedMyGi[1] = false
		else
			local beenSeen = false
			-- check if the item is already in the table in order to prevent the item from being added twice or more times
			for j, seenItem in ipairs(seenCollectibles) do	-- go through each entry of the table of the items the player have seen
				if pickup.SubType == seenItem then
					beenSeen = true
				end
			end
			if beenSeen == false then
				-- add the item to the table
				table.insert(seenCollectibles,1,pickup.SubType)
			end
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_COLLECTIBLE)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_HEART)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_BOMB)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_KEY)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_GRAB_BAG)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_LIL_BATTERY)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_PILL)
GhostShop:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, GhostShop.onCollectibleSpawn, PickupVariant.PICKUP_TAROTCARD)

function GhostShop:onDiceUse(active,rng)
	local room = game:GetRoom()
	local roomType = room:GetType()
	local player = Isaac.GetPlayer(0)

	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and GhostShopVisit == true then
		-- D6, Eternal D6, D Infinity and Dice Shard synergy
		hasUsedDice = true	-- this lets the mod check in the POST_UPDATE if an item in one of the shop slots got rerolled
		-- find items which are not shop items
		for _, entity in pairs(Isaac.FindInRadius(player.Position, 500, EntityPartition.PICKUP)) do
			-- make sure it's a Shop Item
			if not entity:ToPickup():IsShopItem() then
				if entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
					table.insert(rerollTable,1,entity.SubType)
					table.insert(rerollPosition,1,entity.Position)
					entity:Remove() 		-- remove the item which is still there
				end
			end
		end
	end
	-- restock synergy
	dontRestock = true
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onDiceUse, CollectibleType.COLLECTIBLE_D6)
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onDiceUse, CollectibleType.COLLECTIBLE_D_INFINITY)
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onDiceUse, CollectibleType.COLLECTIBLE_ETERNAL_D6)

function GhostShop:onD7Use(active,rng)
	local room = game:GetRoom()
	local roomType = room:GetType()

	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and GhostShopVisit == true then
		hasUsedD7 = true
	end
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onD7Use, CollectibleType.COLLECTIBLE_D7)

function GhostShop:onFlipUse(active,rng)
	local room = game:GetRoom()
	local roomType = room:GetType()
	
	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and GhostShopVisit == true then
		-- Flip synergy
		hasUsedFlip = true	

		-- check for the flipped site
		if flipped == 1	then
			flipped = 2
		elseif flipped == 2 then
			flipped = 1
		end
	end
	-- restock synergy
	dontRestock = true
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onFlipUse, CollectibleType.COLLECTIBLE_FLIP)

function GhostShop:onForgetMeNowUse(active,rng)		-- ! that could still be improved
	-- check if the NormalShopVisit is true
	if NormalShopVisit == true then
		NormalShopVisit = false		-- reset the shop variabel if the player uses the spacebar item
		preFlipped = {}
	end
	-- check if the GhostShopVisit is true
	if GhostShopVisit == true then
		GhostShopVisit = false			-- reset the shop variabel if the player uses the spacebar item
	end
	-- reset the flipped state
	flipped = 1
	-- reset if the shop should stay open
	openNomralShop = false
	-- reset the Glitched Crown check
	hasGlitchedCrown = false
	-- let the game kown that Forget Me Now has been used
	hasUsedFMN = true	-- reset the Forget Me Now use
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onForgetMeNowUse, CollectibleType.COLLECTIBLE_FORGET_ME_NOW)
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onForgetMeNowUse, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)

function GhostShop:onMysteryGiftUse(active,rng)
	local room = game:GetRoom()
	local roomType = room:GetType()
	local quality = rng:RandomInt(5) + 1
	
	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and GhostShopVisit == true then
		hasUsedMyGi[1] = true			-- gets used in the 'MC_POST_PICKUP_INIT'- callback
		hasUsedMyGi[2] = quality		-- gets used in the 'MC_POST_UPDATE'- callback
	end
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, GhostShop.onMysteryGiftUse, CollectibleType.COLLECTIBLE_MYSTERY_GIFT)

function GhostShop:onCreditCardUse(card)
	local room = game:GetRoom()
	local roomType = room:GetType()
	
	-- only use the callback when the player is in the right location
	if roomType == RoomType.ROOM_SHOP	
	and room:IsMirrorWorld() == true 
	and GhostShopVisit == true then
		-- check which flipped side it affects
		if flipped == 1 then
			usedPriceTable = prePrice
			usedFlipTable = preFlipped
		elseif flipped == 2 then
			usedPriceTable = postPrice
			usedFlipTable = postFlipped
		end
		-- reduce the price of the shopt items to 0 
		for i = 1, shopLayouts[usedLayout][1] do			-- counts through 1, 2, 3, 4....
			if shopLayouts[usedLayout][i + 1] ~= nil then	-- go through all the shop item positions
				-- find items which are in the place of the slots
				for _, entity in pairs(Isaac.FindInRadius(shopLayouts[usedLayout][i + 1], 4, EntityPartition.PICKUP)) do
					if usedPriceTable[i] ~= -99 then
						usedPriceTable[i] = 0
					end
					-- add the item to the shoppingList
					if entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
						
						local item = entity
						-- go through the used flipped table
						if usedFlipTable[1] ~= nil then
							
							for j, storedItems in ipairs(usedFlipTable) do
								if storedItems == item.SubType then
									table.insert(shoppingList,1,storedItems) 
								end
							end
						end
					end
				end
			end
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_USE_CARD, GhostShop.onCreditCardUse, Card.CARD_CREDIT)

-- ------------------------------ --
-- store sign & coop ghosts setup --
-- ------------------------------ --
function GhostShop:onGhostSignInit(effect)
	local sprite = effect:GetSprite()
	local data = effect:GetData()

	if data.IsPossessed == nil 
	and data.OnFade == nil then
		data.OnFade = true
		effect:SetColor(Color(0,0,0,0,0,0,0),1,0,false,false)
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, GhostShop.onGhostSignInit, EffectVariant.GHOST_STORE_SIGN)

function GhostShop:onGhostSignUpdate(effect)
	local sprite = effect:GetSprite()
	local data = effect:GetData()

	if data.IsPossessed == true		-- check if the ghost is suppossed to show a little Polty
	and data.ShouldAppear == nil then
		for _, entitis in pairs(Isaac.FindInRadius(effect.Position, 75, EntityPartition.PLAYER)) do
			data.ShouldAppear = true
		end
	end

	if data.ShouldAppear == true then
		-- check if an alt variant of the coop ghost should be spawned 
		local variant = math.random(100)
		if variant <= 5 then 		-- 10% chance meme variants
			sprite:ReplaceSpritesheet(0, "gfx/effects/effect_ghoststoresign_guppy.png")
			sprite:LoadGraphics()
		elseif variant <= 15 then	
			if usedLayout == 1 then		-- unlucky layout
				if data.isAngry == nil then
					data.isAngry = true
				end
			else
				sprite:ReplaceSpritesheet(0, "gfx/effects/effect_ghoststoresign_lost.png")
				sprite:LoadGraphics()
			end
		elseif variant <= 30 then	-- 10% chance rare variants
			sprite:ReplaceSpritesheet(0, "gfx/effects/effect_ghoststoresign_lost.png")
			sprite:LoadGraphics()
		elseif variant <= 66 then	-- 33% chance for other variants
			sprite:ReplaceSpritesheet(0, "gfx/effects/effect_ghoststoresign_afraid.png")
			sprite:LoadGraphics()
			if data.isAfraid == nil then
				data.isAfraid = true
			end
		end
		-- make it appear
		sprite:Play("Appear")
		data.ShouldAppear = false
	end
	if sprite:IsFinished("Appear") then
		if data.isAfraid == true then
			sprite:Play("Afraid", true)
			sprite:LoadGraphics()
		elseif data.isAngry == true then
			sprite:Play("Angry", true)
		else
			sprite:Play("Idle2", true)
		end
	end
	if sprite:IsFinished("Angry") then
		sprite:ReplaceSpritesheet(0, "gfx/effects/effect_ghoststoresign_angry.png")
		sprite:LoadGraphics()
		sprite:Play("Idle3", true)
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, GhostShop.onGhostSignUpdate, EffectVariant.GHOST_STORE_SIGN)

function GhostShop:onCoopGhostUpdate(ghost)
	local sprite = ghost:GetSprite()
	local data = ghost:GetData()
	local sound = SFXManager()

	-- ---------------------------------------- --
	-- update the look the familiar should have -- 
	if data.IdentityUpdate == nil then

		data.IdentityUpdate = true
	
		if data.Identity == 4 
		or data.Identity == 25 then	-- blue color / ??? and T.???
			ghostShop_ReplaceGhost(ghost, "gfx/effects/effect_coop_ghost_blue.png", "gfx/effects/effect_coop_ghost_blue.png") 	-- ghostShop_ReplaceGhost(entity, path1, path2)
			-- sprite:ReplaceSpritesheet(0, "gfx/effects/effect_coop_ghost_blue.png")
			-- sprite:ReplaceSpritesheet(1, "gfx/effects/effect_coop_ghost_blue.png")
			-- sprite:LoadGraphics()
		elseif data.Identity == 7
		or data.Identity == 13
		or data.Identity == 28
		or data.Identity == 32 then	-- dark color / Azazel, T. Azazel, Lilith and T. Lilith
			sprite:ReplaceSpritesheet(0, "gfx/effects/effect_coop_ghost_black.png")
			sprite:ReplaceSpritesheet(1, "gfx/effects/effect_coop_ghost_black.png")
			sprite:LoadGraphics()
		elseif data.Identity == 14
		or data.Identity == 15
		or data.Identity == 16
		or data.Identity == 33
		or data.Identity == 34
		or data.Identity == 35 then	-- Keeper, Apollyon, Forgotten and their tainted versions
			sprite:ReplaceSpritesheet(0, "gfx/effects/effect_coop_ghost_grey.png")
			sprite:ReplaceSpritesheet(1, "gfx/effects/effect_coop_ghost_grey.png")
			sprite:LoadGraphics()
		end
	end

	-- -------------------------------------------------- --
	-- give the coop ghost basic movement via pathfinding --
	if ghost.State == 0 then
		local shouldStop = (math.random(10)) + 1
		if ghost:IsFrame(math.ceil(8/0.5), 0) then
			ghost.Pathfinder:MoveRandomly(true)
		end
		if shouldStop == 1 then		-- 10% to stop moving
			ghost.State = 2
		end
	elseif ghost.State == 2 then
		-- ghost.Pathfinder:Reset(true)
		ghost.Velocity = Vector(0,0)
		if ghost:IsFrame(math.ceil(32/0.5), 0) then
			ghost.Pathfinder:MoveRandomly(true)
			ghost.State = 0
		end
	end

	-- --------------------------------------------------- --
	-- kill the coop ghost and spawn an item from it's pool --
	if data.IsDying == true
	and not sprite:IsPlaying("Death") then
		sprite:Play("Death")
	end
	if sprite:IsPlaying("Death") then
		local ghostTable = data.HasTable 				-- stores the table the item should be spawned from
		ghost.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE	-- it's shouldn't collide with anyhting once it's dead
		ghost.Velocity = Vector(0,0)

		if data.itemSpawned == nil 
		and storedCoopItems[ghostTable][2] ~= nil then		-- needs a tleast an item to spawn 

			-- get the rng
			local ghostRNG = RNG()
			ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

			-- spawn the item
			local decoyTable = {}		-- stores the item which the players don't have at the moment
			local tableChecked = 1

			while decoyTable[1] == nil and tableChecked ~= 5 do				-- while the decoy table is still empty and table hasn't been checked
				if storedCoopItems[ghostTable][2] ~= nil then 				-- needs to be checked, because we could have decreased the quality again
					-- first we have to check which items the players from the curerent quality table already have
					-- we also need to get the current amount of items in the og table
					for a, curItem in ipairs(storedCoopItems[ghostTable]) do	-- go through each entry of the current quality table
						local playerHasCurItem = false

						if storedCoopItems[ghostTable][a + 1] ~= nil then	-- we have to check the second place and onward as the first place is reserved for the characters id
							for j = 0, (game:GetNumPlayers() - 1) do
								local player = Isaac.GetPlayer(j)
								-- check if the player has the item
								if player:IsCoopGhost() == false
								and player:HasCollectible(storedCoopItems[ghostTable][a + 1]) then
									playerHasCurItem = true
								end
							end
							if playerHasCurItem == false then		-- none of the players have the item currently
								table.insert(decoyTable, storedCoopItems[ghostTable][a + 1])	-- insert the items into the decoy table
							end
						end
					end
				end
				-- check if the decoy table empty or not (if empty than the players have the current items already)
				if decoyTable[1] == nil then
					-- check if we are already at the quality 0 table
					tableChecked = 5

				-- else the while loop breaks next round and we can progress
				end
			end
			if decoyTable[1] ~= nil then		-- if there are items to chose from
				-- we have at least one item in the table, so we can try to spawn something!
				local itemPosition = ghostRNG:RandomInt(#decoyTable) + 1
				local poolRNG = decoyTable[itemPosition]
				local shopItem = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, poolRNG, ghost.Position, Vector(0,0), nil) -- :ToPickup()
			end

			-- block the coop table so that the ghost can't be spawned again
			storedCoopItems[ghostTable][1] = -1

			-- prevent that more than one item spawns
			data.itemSpawned = true
		end
	end
	if sprite:IsEventTriggered("Sound") then
		-- play the baby hurt sound effect
		sound:Play(SoundEffect.SOUND_BABY_HURT, 0.3, 0, false, 0.7)
	end
	if sprite:IsFinished("Death") then
		ghost:Remove()
	end
end
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onCoopGhostUpdate, GhostShopMod.ENTITY_GS_COOP_GHOST)

function GhostShop:onCoopGhostDeath(target, dmg, flag, souce, countdown)
	local sprite = target:GetSprite()
	local data = target:GetData()
	-- basically checks if the ghost got hit by a explosion. However to trigger the custom code we have kill it off in the 'MC_NPC_UPDATE' callback above
	if flag & DamageFlag.DAMAGE_EXPLOSION > 0  then
		-- It's dead ._.
		if data.IsDying == nil then
			data.IsDying = true
		end
		return false
	else
		return false
	end
end
GhostShop:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, GhostShop.onCoopGhostDeath, GhostShopMod.ENTITY_GS_COOP_GHOST)

--------------------
-- MC_EXECUTE_CMD --
--------------------
function GhostShop:executeCommand(cmd, params)
    params = split(params)

	if cmd == "gs" then
		if params[1] == "clear"
		and params[2] == "tables" then
			ghostShop_ItemCompatibility(2)
			print("updated stored items")
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_EXECUTE_CMD, GhostShop.executeCommand)

-- ----------- --
-- save & exit --
-- ----------- --
function GhostShop:onExit(_)
	local itemConfig = Isaac.GetItemConfig()
	local level = game:GetLevel()
	local stage = level:GetStage()
	local stageType = level:GetStageType()

	-- -------------------------------------------------------- --
	-- reset Gamestate tables which track the current held items--
	GameState.savedItems1 = {}
	GameState.savedItems2 = {}
	GameState.savedItems3 = {}
	GameState.savedItems4 = {}
	GameState.savedItems5 = {}
	-- coop ghosts
	GameState.coopItems1 = {}
	GameState.coopItems2 = {}
	GameState.coopItems3 = {}

	-- ------------------------------------------------------------------------- --
	-- update the backup Gamestate tables in case items have been spawned/bought --
	-- update the json tables once an invalid item has been found
	GameState.backupItems1 = storedItems[1]
	GameState.backupItems2 = storedItems[2]
	GameState.backupItems3 = storedItems[3]
	GameState.backupItems4 = storedItems[4]
	GameState.backupItems5 = storedItems[5]

	GameState.backUpCoopItems1 = storedCoopItems[1]
	GameState.backUpCoopItems2 = storedCoopItems[2]
	GameState.backUpCoopItems3 = storedCoopItems[3]

	-- ---------------------- --
	-- update Gamestate tables --
	-- usedLayout & itemQaulity
	GameState.backUpLayout = usedLayout
	GameState.backUpQuality = itemQuality

	-- win & death bonus
	GameState.deathBonus = deathBonus
	GameState.winBonus = winBonus

	-- seenItems
	GameState.seenItems = seenCollectibles		-- refill the table with the seen items in the current run
	
	-- the different shopping lists
	GameState.shoppingList = shoppingList
	GameState.backupShoppingListOne = backupListOne
	GameState.backupShoppingListTwo = backupListTwo

	-- the different item prices
	GameState.prePrice = prePrice	
	GameState.postPrice = postPrice
	GameState.preAddRestockPrice = preAddRestockPrice	
	GameState.postAddRestockPrice = postAddRestockPrice

	-- save which side we are currently flipped to. -2 is the indicator for the normal layout, -3 is the one for the flipped layout
	if preFlipped[1] ~= nil then	-- we make sure the item were spawned in the ghost shop
		if preFlipped[(shopLayouts[usedLayout][1]) + 1] == nil then
			if flipped == 1 then		
				table.insert(preFlipped, -2)
			elseif flipped == 2 then	
				table.insert(preFlipped, -3)
			end
		else
			if flipped == 1 then		
				preFlipped[(shopLayouts[usedLayout][1]) + 1] = -2
			elseif flipped == 2 then	
				preFlipped[(shopLayouts[usedLayout][1]) + 1] = -3
			end
		end
	end
	-- update the preFlipped tables with the items which are currently in them
	GameState.preFlippedItems = preFlipped		
	GameState.postFlippedItems = postFlipped

	-- update and check if one of the coop ghost died and spanwed it's item. -1 is here the indicator for that and get's saved on the first position of the table
	for g = 1,3 do
		if storedCoopItems[g][1] == -1 then
			GameState.backUpCoopItems1[1] = -1
		elseif storedCoopItems[g][1] == -1 then
			GameState.backUpCoopItems2[1] = -1
		elseif storedCoopItems[g][1] == -1 then
			GameState.backUpCoopItems3[1] = -1
		end
	end

	-- ------------------------------------------------------------------- --
	-- update the Gamestate tables with the items the player(s) currently has --
	for i = 0, (game:GetNumPlayers() - 1) do
		local player = Isaac.GetPlayer(i)
		local playerData = player:GetData()

		-- store the character id from coop players for the lil coop ghosts. This allows to know which characters were used in the last run
		if i == 1 then		-- player 2
			table.insert(GameState.coopItems1, 1, player:GetPlayerType())
		elseif i == 2 then	-- player 3
			table.insert(GameState.coopItems2, 1, player:GetPlayerType())
		elseif i == 3 then	-- player 4
			table.insert(GameState.coopItems3, 1, player:GetPlayerType())
		end

		-- check if the player dies in the mother chase	
		if (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
		and stage == LevelStage.STAGE2_2	
		and GetDimension(level) == 1 then	-- should detect the Mine Chase (thanks to Wolfsauge)

			-- go through their corresponding temporary table and check their quality
			for k, itemID in ipairs(temporaryStored[(i + 1)]) do

				-- save the item the player currently has
					ghostShop_SaveHeldItems(itemID, i)		-- ghostShop_SaveHeldItems(ID of the item, coop player)
			end
		else
			-- check if the player is a coop ghost
			if player:IsCoopGhost() == false then
				-- go through all normal items
				for j = 1, numCollectibles do

					if Isaac.GetItemConfig():GetCollectible(j) ~= nil
					and player:HasCollectible(j) then

						-- check if one of the items shoudn't be saved
						if ghostShop_ItemBlacklist(j) == true then		-- ghostShop_ItemBlacklist(ID of the item)
							-- save the item the player currently has
							ghostShop_SaveHeldItems(j, i)			-- ghostShop_SaveHeldItems(ID of the item, coop player)
						end
					end
				end
			else		-- ...so the player is a coop ghost
				-- go through their corresponding temporary item table and check the quality of them
				for k, itemID in ipairs(temporaryStored[(i + 1)]) do

					-- save the item the player currently has
					ghostShop_SaveHeldItems(itemID, i)			-- ghostShop_SaveHeldItems(ID of the item, coop player)
				end
			end
		end
	end
	-- save the data
	Isaac.SaveModData(GhostShop, json.encode(GameState))	-- encodes the data
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, GhostShop.onExit)
GhostShop:AddCallback(ModCallbacks.MC_POST_GAME_END, GhostShop.onExit)