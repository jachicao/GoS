-- Source: https://github.com/w8r/GreinerHormann
--[[
        Greiner Hormann Algorithm for Clipping Polygons
        Credits to Alexander Milevski (https://github.com/w8r/GreinerHormann)

    0.1 release
--]]

_G.GreinerHormannVersion = 0.1;

local function xor(p, q)
	return (p and not q) or (not p and q);
end

local function isArray(x)
	if type(x) == "table" then
		if x.x then
			return false;
		end
		return true;
	end
	return false;
end

local function doWhile(condition, statement)
	local bool = true;

	while bool or condition() do
		statement();
		bool = false;
	end
end

class "GreinerHormann"

	function GreinerHormann:__init()

	end
    --[[
		@param  {Array.<Array.<Number>|Array.<Object>} polygonA
		@param  {Array.<Array.<Number>|Array.<Object>} polygonB
		@return {Array.<Array.<Number>>|Array.<Array.<Object>|Null}
    --]]
	function GreinerHormann:union(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, false);
	end

    --[[
		@param  {Array.<Array.<Number>|Array.<Object>} polygonA
		@param  {Array.<Array.<Number>|Array.<Object>} polygonB
		@return {Array.<Array.<Number>>|Array.<Array.<Object>>|Null}
    --]]
	function GreinerHormann:intersection(polygonA, polygonB)
		return self:clip(polygonA, polygonB, true, true);
	end

    --[[
		@param  {Array.<Array.<Number>|Array.<Object>} polygonA
		@param  {Array.<Array.<Number>|Array.<Object>} polygonB
		@return {Array.<Array.<Number>>|Array.<Array.<Object>>|Null}
    --]]
	function GreinerHormann:diff(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, true);
	end

    --[[
		@param  {Array.<Array.<Number>|Array.<Object>} polygonA
		@param  {Array.<Array.<Number>>} polygonA
		@param  {Array.<Array.<Number>>} polygonB
		@param  {Boolean}                sourceForwards
		@param  {Boolean}                clipForwards
		@return {Array.<Array.<Number>>}
    --]]
	function GreinerHormann:clip(polygonA, polygonB, eA, eB)
		local source = GreinerHormannPolygon(polygonA);
		local clip = GreinerHormannPolygon(polygonB);
		return source:clip(clip, eA, eB);
	end

class "GreinerHormannPolygon"

    --[[
		Polygon representation
		@param {Array.<Array.<Number>>} p
		@param {Boolean=}               arrayVertices
		
		@constructor
    --]]
	function GreinerHormannPolygon:__init(p, arrayVertices)
		self.first = nil;
		self.vertices = 0;
		self._lastUnprocessed = nil;
		self._arrayVertices = nil;

		if not arrayVertices then
			self._arrayVertices = isArray(p[1]);
		else
			self._arrayVertices = arrayVertices;
		end

		for i, point in ipairs(p) do
			self:addVertex(GreinerHormannVertex(point));
		end
	end

    --[[
		Add a vertex object to the polygon
		(vertex is added at the 'end' of the list')
		
		@param vertex
    --]]
	function GreinerHormannPolygon:addVertex(vertex)
		if self.first == nil then
			self.first = vertex;
			self.first.next = vertex;
			self.first.prev = vertex;
		else
			local nxt = self.first;
			local prev = nxt.prev;

			next.prev = vertex;
			vertex.next = nxt;
			vertex.prev = prev;
			prev.next = vertex;
		end
		self.vertices = self.vertices + 1;
	end

    --[[
		Inserts a vertex inbetween start and end
		
		@param {Vertex} vertex
		@param {Vertex} start
		@param {Vertex} end
    --]]
	function GreinerHormannPolygon:insertVertex(vertex, start, end1)
		local prev = nil;
		local curr = start;

		while (not curr:equals(end1)) and curr._distance < vertex._distance do
			curr = curr.next;
		end

		vertex.next = curr;
		prev = curr.prev;

		vertex.prev = prev;
		prev.next = vertex;
		curr.prev = vertex;

		self.vertices = self.vertices + 1;
	end

    --[[
		Get next non-intersection point
		@param  {Vertex} v
		@return {Vertex}
    --]]
	function GreinerHormannPolygon:getNext(v)
		local c = v;
		while c._isIntersection do
			c = c.next;
		end
		return c;
	end

    --[[
		Unvisited intersection
		@return {Vertex}
    --]]
	function GreinerHormannPolygon:getFirstIntersect()
		local v = self._firstIntersect and self._firstIntersect or self.first;

		local bool = true;
		while bool or (not v:equals(self.first)) do
			if v._isIntersection and not v._visited then
				break;
			end
			v = v.next;
			bool = false;
		end

		self._firstIntersect = v;
		return v;
	end

    --[[
		Does the polygon have unvisited vertices
		@return {Boolean} [description]
    --]]
	function GreinerHormannPolygon:hasUnprocessed()
		local v = self._lastUnprocessed and self._lastUnprocessed or self.first;

		local bool = true;
		while bool or (not v:equals(self.first)) do
			if v._isIntersection and not v._visited then
				self._lastUnprocessed = v;
				return true;
			end
			bool = false;
		end

		self._lastUnprocessed = nil;
		return false;
	end

    --[[
		The output depends on what you put in, arrays or objects
		@return {Array.<Array<Number>|Array.<Object>}
    --]]
	function GreinerHormannPolygon:getPoints()
		local points = {};
		local v = self.first;

		if self._arrayVertices then
			doWhile(
				function() return v ~= self.first end,
				function()
					local t = {};
					table.insert(t, v.x);
					table.insert(t, v.y);
					table.insert(t, v.z);
					table.insert(points, t)
					v = v.next;
				end
			);
		else
			doWhile(
				function() return v ~= self.first end,
				function()
					table.insert(points, {
						x = v.x,
						y = v.y,
						z = v.z
					});
					v = v.next;
				end
			);
		end
		return points;
	end

    --[[
		Clip polygon against another one.
		Result depends on algorithm direction:
		
		Intersection: forwards forwards
		Union:        backwars backwards
		Diff:         backwards forwards
		
		@param {Polygon} clip
		@param {Boolean} sourceForwards
		@param {Boolean} clipForwards
    --]]
	function GreinerHormannPolygon:clip(clip, sourceForwards, clipForwards)
		local sourceVertex = self.first;
		local clipVertex = clip.first;
		local sourceInClip = nil;
		local clipInSource = nil;

		-- calculate and mark intersections
		doWhile(
			function() return not sourceVertex:equals(self.first) end,
			function()
				if not sourceVertex._isIntersection then
					doWhile(
						function() return not sourceVertex:equals(clip.first) end,
						function()
							if not clipVertex._isIntersection then
								local i = GreinerHormannIntersection(sourceVertex, self:getNext(sourceVertex.next), clipVertex, clip:getNext(clipVertex.next));
								if i:valid() then
									local sourceIntersection = GreinerHormannVertex.createIntersection(i.x, i.y, i.z, i.toSource);
									local clipIntersection = GreinerHormannVertex.createIntersection(i.x, i.y, i.z, i.toClip);

									sourceIntersection._corresponding = clipIntersection;
									clipIntersection._corresponding = sourceIntersection;

									self:insertVertex(
										sourceIntersection,
										sourceVertex,
										self:getNext(sourceVertex.next));

									clip:insertVertex(
										clipIntersection,
										clipVertex,
										clip:getNext(clipVertex.next));
								end
							end
							clipVertex = clipVertex.next;
						end
					);
				end

				sourceVertex = sourceVertex.next;
			end
		);

		-- phase two - identify entry/exit points
		sourceVertex = self.first;
		clipVertex = clip.first;

		sourceInClip = sourceVertex:isInside(clip);
		clipInSource = clipVertex:isInside(self);

		sourceForwards = xor(sourceForwards, sourceInClip);
		clipForwards = xor(clipForwards, clipInSource);

		doWhile(
			function() return not sourceVertex:equals(self.first) end,
			function()
				if sourceVertex._isIntersection then
					sourceVertex._isEntry = sourceForwards;
					sourceForwards = not sourceForwards;
				end
				sourceVertex = sourceVertex.next;
			end
		);

		doWhile(
			function() return not clipVertex:equals(clip.first) end,
			function()
				if clipVertex._isIntersection then
					clipVertex._isEntry = clipForwards;
					clipForwards = not clipForwards;
				end
				clipVertex = clipVertex.next;
			end
		);

		-- phase three - construct a list of clipped polygons
		local list = {};

		while self:hasUnprocessed() do
			local current = self:getFirstIntersect();
			-- keep format
			local clipped = GreinerHormannPolygon({}, self._arrayVertices);
			clipped:addVertex(GreinerHormannVertex(current.x, current.y, current.z));

			doWhile(
				function() return not current._visited end,
				function()
					current:visit();
					if current._isEntry then
						doWhile(
							function() return not current._isIntersection end,
							function()
								current = current.next;
								clipped:addVertex(GreinerHormannVertex(current.x, current.y, current.z));
							end
						);
					else
						doWhile(
							function() return not current._isIntersection end,
							function()
								current = current.prev;
								clipped:addVertex(GreinerHormannVertex(current.x, current.y, current.z));
							end
						);
					end
				end
			);
			table.insert(list, clipped:getPoints());
		end

		if #list == 0 then
			if sourceInClip then
				table.insert(list, self:getPoints());
			end
			if clipInSource then
				table.insert(list, clip:getPoints());
			end
			if #list == 0 then
				list = nil;
			end
		end
		return list;
	end

class "GreinerHormannVertex"

	--[[
		Vertex representation
		
		@param {Number|Array.<Number>} x
		@param {Number=}               y
		
		@constructor
    --]]
	function GreinerHormannVertex:__init(x, y, z)

		if not y then
			-- Coords
			if isArray(x) then
				x = x[1];
				y = x[2];
				z = x[3];
			else
				z = x.z;
				y = x.y;
				x = x.x;
			end
		end

		self.x = x;
		self.y = y;
		self.z = z;
		self.next = nil;
		self.prev = nil;
		self._corresponding = nil;
		self._distance = 0.0;
		self._isEntry = true;
		self._isIntersection = false;
		self._visited = false;
	end

	--[[
		Creates intersection vertex
		@param  {Number} x
		@param  {Number} y
		@param  {Number} distance
		@return {Vertex}
    --]]
	function GreinerHormannVertex.createIntersection(x, y, z, distance)
		local vertex = GreinerHormannVertex(x, y, z);
		vertex._distance = distance;
		vertex._isIntersection = true;
		vertex._isEntry = false;
		return vertex;
	end

	--[[
		Mark as visited
    --]]
	function GreinerHormannVertex:visit()
		self._visited = true;
		if self._corresponding ~= nil and not self._corresponding._visited then
			self._corresponding:visit();
		end
	end

	--[[
		Convenience
    --]]
	function GreinerHormannVertex:equals(v)
		return self.x == v.x and self.y == v.y;
	end

	--[[
		Check if vertex is inside a polygon by odd-even rule:
		If the number of intersections of a ray out of the point and polygon
		segments is odd - the point is inside.
		@param {Polygon} poly
		@return {Boolean}
    --]]
	function GreinerHormannVertex:isInside(poly)
		local oddNodes = false;
		local vertex = poly.first;
		local nxt = vertex.next;
		local x = self.x;
		local y = self.y;

		doWhile(
			function() return not vertex:equals(poly.first) end,
			function()
				if (vertex.y < y and nxt.y >= y or nxt.y < y and vertex.y >= y) and (vertex.x <= x or nxt.x <= x) then
					oddNodes = xor(oddNodes, (vertex.x + (y - vertex.y) / (next.y - vertex.y) * (next.x - vertex.x) < x));
				end
				vertex = vertex.next;
				nxt = vertex.next and vertex.next or poly.first;
			end
		);

		return oddNodes;
	end

class "GreinerHormannIntersection"

	--[[
		Intersection
		@param {Vertex} s1
		@param {Vertex} s2
		@param {Vertex} c1
		@param {Vertex} c2
		@constructor
    --]]
	function GreinerHormannIntersection:__init(s1, s2, c1, c2)
		self.x = 0.0;
		self.y = 0.0;
		self.z = 0.0;
		if s1.z and s2.z and c1.z and c2.z then
			self.z = (s1.z + s2.z + c1.z + c2.z) / 4;
		end
		self.toSource = 0.0;
		self.toClip = 0.0;

		local d = (c2.y - c1.y) * (s2.x - s1.x) - (c2.x - c1.x) * (s2.y - s1.y);

		if d == 0 then
			return;
		end

		self.toSource = ((c2.x - c1.x) * (s1.y - c1.y) - (c2.y - c1.y) * (s1.x - c1.x)) / d;
		self.toClip = ((s2.x - s1.x) * (s1.y - c1.y) - (s2.y - s1.y) * (s1.x - c1.x)) / d;

		if self:valid() then
			self.x = s1.x + self.toSource * (s2.x - s1.x);
			self.y = s1.y + self.toSource * (s2.y - s1.y);
		end
	end

	--[[
		@return {Boolean}
    --]]
	function GreinerHormannIntersection:valid()
		return (0 < self.toSource and self.toSource < 1) and (0 < self.toClip and self.toClip < 1);
	end