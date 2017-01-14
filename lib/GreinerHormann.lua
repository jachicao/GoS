-- Source: https://github.com/w8r/GreinerHormann

local function xor(p, q)
	return (p and not q) or (not p and q)
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

class "GreinerHormann"

	function GreinerHormann:__init()

	end

	function GreinerHormann:union(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, false);
	end

	function GreinerHormann:intersection(polygonA, polygonB)
		return self:clip(polygonA, polygonB, true, true);
	end

	function GreinerHormann:diff(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, true);
	end

	function GreinerHormann:clip(polygonA, polygonB, eA, eB)
		local source = GreinerHormannPolygon(polygonA);
		local clip = GreinerHormannPolygon(polygonB);
		return source:clip(clip, eA, eB);
	end

class "GreinerHormannPolygon"

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

		-- TODO: Check
		for i, point in ipairs(p) do
			self:addVertex(GreinerHormannVertex(point));
		end
	end

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

	function GreinerHormannPolygon:insertVertex(vertex, start, end1)
		local prev = start;
		local curr = start;

		while not curr:equals(end1) and curr._distance < vertex._distance do
			curr = curr.next;
		end

		vertex.next = curr;
		prev = curr.prev;

		vertex.prev = prev;
		prev.next = vertex;
		curr.prev = vertex;

		self.vertices = self.vertices + 1;
	end

	function GreinerHormannPolygon:getNext(v)
		local c = v;
		while c._isIntersection do
			c = c.next;
		end
		return c;
	end

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

	function GreinerHormannPolygon:getPoints()
		local points = {};
		local v = self.first;

		if self._arrayVertices then
			local bool = true;
			while bool or (v ~= self.first) do
				local t = {};
				table.insert(t, v.x);
				table.insert(t, v.y);
				table.insert(points, t)
				v = v.next;
				bool = false;
			end
		else
			local bool = true;
			while bool or (v ~= self.first)	 do
				table.insert(points, {
					x = v.x,
					y = v.y
				})
				v = v.next;
				bool = false;
			end
		end
		return points;
	end

	function GreinerHormannPolygon:clip(clip, sourceForwards, clipForwards)
		local sourceVertex = self.first;
		local clipVertex = clip.first;
		local sourceInClip = nil;
		local clipInSource = nil;

		local bool1 = true;
		while bool1 or (not sourceVertex:equals(self.first)) do
			if not sourceVertex._isIntersection then
				local bool2 = true;
				while bool2 or (not sourceVertex:equals(clip.first)) do
					if not clipVertex._isIntersection then
						local i = GreinerHormannIntersection(sourceVertex, self:getNext(sourceVertex.next), clipVertex, clip:getNext(clipVertex.next));
						if i:valid() then
							local sourceIntersection = GreinerHormannVertex.createIntersection(i.x, i.y, i.toSource);	
							local clipIntersection = GreinerHormannVertex.createIntersection(i.x, i.y, i.toClip);

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
					bool2 = false;
				end
			end

			sourceVertex = sourceVertex.next;
			bool1 = false;
		end
		sourceVertex = self.first;
		clipVertex = clip.first;

		sourceInClip = sourceVertex:isInside(clip);
		clipInSource = clipVertex:isInside(self);

		sourceForwards = xor(sourceForwards, sourceInClip);
		clipForwards = xor(clipForwards, clipInSource);

		local bool3 = true;
		while bool3 or (not sourceVertex:equals(self.first)) do
			if sourceVertex._isIntersection then
				sourceVertex._isEntry = sourceForwards;
				sourceForwards = not sourceForwards;
			end
			sourceVertex = sourceVertex.next;
			bool3 = false;
		end

		local bool4 = true;
		while bool4 or (not clipVertex:equals(clip.first)) do
			if clipVertex._isIntersection then
				clipVertex._isEntry = clipForwards;
				clipForwards = not clipForwards;
			end
			clipVertex = clipVertex.next;
			bool4 = false;
		end

		local list = {};

		while self:hasUnprocessed() do
			local current = self:getFirstIntersect();
			local clipped = GreinerHormannPolygon({}, self._arrayVertices);
			clipped:addVertex(GreinerHormannVertex(current.x, current.y));

			local bool5 = true;
			while bool5 or (not current._visited) do
				current:visit();
				if current._isEntry then
					local bool6 = true;
					while bool6 or (not current._isIntersection) do
						current = current.next;
						clipped:addVertex(GreinerHormannVertex(current.x, current.y));
						bool6 = false;
					end
				else
					local bool7 = true;
					while bool7 or (not current._isIntersection) do
						current = current.prev;
						clipped:addVertex(GreinerHormannVertex(current.x, current.y));
						bool7 = false;
					end
				end
				bool5 = false;
			end
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
	
	function GreinerHormannVertex:__init(x, y)

		if not y then
			if isArray(x) then
				x = x[1];
				y = x[2];
			else
				y = x.y;
				x = x.x;
			end
		end

		self.x = x;
		self.y = y;
		self.next = nil;
		self.prev = nil;
		self._corresponding = nil;
		self._distance = 0.0;
		self._isEntry = true;
		self._isIntersection = false;
		self._visited = false;
	end

	function GreinerHormannVertex.createIntersection(x, y, distance)
		local vertex = GreinerHormannVertex(x, y);
		vertex._distance = distance;
		vertex._isIntersection = true;
		vertex._isEntry = false;
		return vertex;
	end

	function GreinerHormannVertex:visit()
		self._visited = true;
		if self._corresponding ~= nil and not self._corresponding._visited then
			self._corresponding:visit();
		end
	end

	function GreinerHormannVertex:equals(v)
		return self.x == v.x and self.y == v.y;
	end

	function GreinerHormannVertex:isInside(poly)
		local oddNodes = false;
		local vertex = poly.first;
		local nxt = vertex.next;
		local x = self.x;
		local y = self.y;

		local bool = true;
		while bool or (not vertex:equals(poly.first)) do
			if (vertex.y < y and nxt.y >= y or nxt.y < y and vertex.y >= y) and (vertex.x <= x or nxt.x <= x) then
				oddNodes = xor(oddNodes, (vertex.x + (y - vertex.y) / (next.y - vertex.y) * (next.x - vertex.x) < x));
			end
			vertex = vertex.next;
			nxt = vertex.next and vertex.next or poly.first;
			bool = false;
		end

		return oddNodes;
	end

class "GreinerHormannIntersection"

	function GreinerHormannIntersection:__init(s1, s2, c1, c2)
		self.x = 0.0;
		self.y = 0.0;
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

	function GreinerHormannIntersection:valid()
		return (0 < self.toSource and self.toSource < 1) and (0 < self.toClip and self.toClip < 1);
	end