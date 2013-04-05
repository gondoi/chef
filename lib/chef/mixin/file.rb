# Author:: BK Box <bk@theboxes.org>
# Copyright:: Copyright (c) 2011-2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
class File
  def flocked? &block
    flockstruct = [Fcntl::F_RDLCK, 0, 0, 0, 0].pack("ssqqi")
    fcntl Fcntl::F_GETLK, flockstruct
    status = flockstruct.unpack("ssqqi")[0]
    case status
      when Fcntl::F_UNLCK
        return false
      when Fcntl::F_WRLCK|Fcntl::F_RDLCK
        return true
      else
        raise SystemCallError, status
    end
  end
  alias_method "if_not_flocked", "flocked?"
end
